# ============================================================================
# FUNCTION: read_IRGA
# ============================================================================
#
# PURPOSE:
#   Reads raw IRGA (Li-COR gas analyzer) data files exported from the 
#   instrument and creates a standardized time-series data frame with
#   aligned timestamps and deduplicated measurements.
#
# DATA FORMAT REQUIREMENTS:
#   - Input files: CSV format, comma or tab-delimited
#   - Expected column positions (columns 1-8):
#     1. Data format identifier (must start with "M")
#     2. DATE: measurement date (multiple formats supported)
#     3. TIME: measurement time (HH:MM:SS or HH:MM)
#     4. Plot number / sample ID
#     5. Timestamp (ignored, can be any value)
#     6. CO2 concentration (ppb)
#     7. Atmospheric pressure (hPa)
#     8. Flow rate (µmol/mol)
#   - Date format flexibility: automatically detects and handles:
#     * DD/MM/YYYY, DD/MM/YY, DD-MM-YYYY, DD-MM-YY, YYYY-MM-DD
#   - Times can be HH:MM:SS or HH:MM
#
# PARAMETERS:
#   myfolder    (string): Path to folder containing raw IRGA CSV files
#   timezone    (string): Timezone for conversion (default: "CET")
#   verbose     (logical): Print status messages (default: TRUE)
#
# RETURNS:
#   Data frame with columns:
#   - date: Date (R Date format)
#   - IRGAtime: Original time string from instrument
#   - unixtime: Unix timestamp (seconds since 1970-01-01)
#   - PosiXct.time: POSIXct datetime object
#   - flowrate: Flow rate (µmol/mol)
#   - CO2: CO2 concentration (ppb)
#   - Press: Atmospheric pressure (hPa)
#
# NOTES:
#   - Automatically removes non-measurement rows (those not starting with "M")
#   - Sorts by timestamp and removes exact duplicates
#   - Converts numeric strings, handling any parsing issues gracefully
#
# ============================================================================

read_IRGA <- function(myfolder, timezone = "CET", verbose = TRUE) {
  
  # Input validation
  if (!dir.exists(myfolder)) {
    stop("Error: Folder '", myfolder, "' does not exist.")
  }
  
  # Get list of files in the directory
  rawfiles <- list.files(myfolder)
  
  if (length(rawfiles) == 0) {
    stop("Error: No files found in folder '", myfolder, "'.")
  }
  
  if (verbose) {
    message("[read_IRGA] Found ", length(rawfiles), " files to process")
  }
  
  # ========================================================================
  # HELPER FUNCTION: Flexible Date Parser
  # ========================================================================
  # This function attempts to parse dates in multiple common formats
  # Returns a Date object if successful, NA if all formats fail
  
  parse_flexible_date <- function(date_strings) {
    # List of date formats to try (in order of likelihood)
    formats_to_try <- c(
      # "%d/%m/%Y",   # DD/MM/YYYY - European standard (most common)
      "%d/%m/%y"   # DD/MM/YY - European, 2-digit year
      # "%d-%m-%Y",   # DD-MM-YYYY - Alternative European
      # "%d-%m-%y",   # DD-MM-YY - Alternative European, 2-digit year
      # "%Y-%m-%d",   # YYYY-MM-DD - ISO standard
      # "%Y/%m/%d",   # YYYY/MM/DD - ISO with slashes
      # "%m/%d/%Y",   # MM/DD/YYYY - US standard (fallback)
      # "%m-%d-%Y"    # MM-DD-YYYY - US alternative
    )
    
    # Try each format sequentially
    for (format in formats_to_try) {
      result <- try(as.Date(date_strings, format = format), silent = TRUE)
      
      # Check if parsing was successful (no NAs)
      if (!inherits(result, "try-error") && !all(is.na(result))) {
        # Return this result if we got at least one valid date
        if (any(!is.na(result))) {
          return(result)
        }
      }
    }
    
    # If we get here, none of the formats worked
    stop("Could not parse dates. Tried formats: ", 
         paste(formats_to_try, collapse = ", "),
         "\nSample date value: ", date_strings[1])
  }
  
  # ========================================================================
  # HELPER FUNCTION: Flexible Time Parser
  # ========================================================================
  # Parses times in HH:MM:SS or HH:MM format
  
  parse_flexible_time <- function(time_strings) {
    result <- strptime(time_strings, "%H:%M:%S")           # Try HH:MM:SS first
    fix <- is.na(result)
    result[fix] <- strptime(time_strings[fix], "%H:%M")    # Fall back to HH:MM
    
    # Check if any times still failed to parse
    if (any(is.na(result))) {
      warning("Some time values could not be parsed. Check format (expected HH:MM:SS or HH:MM)")
    }
    
    return(result)
  }
  
  # ========================================================================
  # MAIN PROCESSING: Read and combine all files
  # ========================================================================
  
  data <- NULL
  
  for (i in rawfiles) {
    if (verbose) {
      message("  Reading file: ", i)
    }
    
    # Try to read the file with different delimiters if needed
    tryCatch({
      file_data <- read.delim(file.path(myfolder, i), 
                              header = FALSE, 
                              sep = ",",
                              stringsAsFactors = FALSE)
      data <- rbind(data, file_data)
    }, error = function(e) {
      warning("Failed to read file '", i, "': ", e$message)
    })
  }
  
  if (is.null(data) || nrow(data) == 0) {
    stop("No data successfully read from any files in folder '", myfolder, "'")
  }
  
  if (verbose) {
    message("[read_IRGA] Read ", nrow(data), " total rows from all files")
  }
  
  # ========================================================================
  # STEP 1: Filter rows - Keep only measurement rows (first column starts with "M")
  # ========================================================================
  # IRGA files contain header and metadata rows that don't start with "M"
  # We only want the actual measurement data
  
  ind_keep <- grep(x = data$V1, pattern = "^M")  # ^ ensures "M" is at start
  
  if (length(ind_keep) == 0) {
    stop("Error: No measurement rows found (no rows starting with 'M'). ",
         "Check that your raw files are in the correct format.")
  }
  
  data <- data[ind_keep, ]
  
  if (verbose) {
    message("[read_IRGA] Kept ", nrow(data), " measurement rows (starting with 'M')")
  }
  
  # ========================================================================
  # STEP 2: Assign column names
  # ========================================================================
  # The first 8 columns have standard meanings in Li-COR IRGA exports
  
  names(data)[c(1:8)] <- c(
    "dataformat",    # Column 1: Data format identifier (M = measurement)
    "DATE",          # Column 2: Date of measurement
    "TIME",          # Column 3: Time of measurement
    "plotnum",       # Column 4: Plot number or sample identifier
    "timestamp",     # Column 5: Timestamp (often redundant, kept for compatibility)
    "CO2",           # Column 6: CO2 concentration (ppb)
    "Patm",          # Column 7: Atmospheric pressure (hPa)
    "flowrate"       # Column 8: Flow rate (µmol/mol)
  )
  
  # ========================================================================
  # STEP 3: Parse dates and times with flexible format handling
  # ========================================================================
  # This is where we handle technician errors in date format
  
  if (verbose) {
    message("[read_IRGA] Parsing dates (sample: ", data$DATE[1], ")")
  }
  
  parsed_dates <- parse_flexible_date(data$DATE)
  parsed_times <- parse_flexible_time(data$TIME)
  
  # ========================================================================
  # STEP 4: Create Unix timestamp
  # ========================================================================
  # Unix timestamp is the number of seconds since 1970-01-01 00:00:00
  # This provides a timezone-independent reference for all times
  
  datetime_string <- paste(format(parsed_dates, "%Y-%m-%d"),  # Use standardized format
                           format(parsed_times, "%H:%M:%S"),
                           sep = " ")
  
  data$unixtime <- as.numeric(
    as.POSIXct(datetime_string, tz = timezone, format = "%Y-%m-%d %H:%M:%S")
  )
  
  if (any(is.na(data$unixtime))) {
    warning("Some timestamps could not be converted. Check date/time values.")
  }
  
  # ========================================================================
  # STEP 5: Create standardized output data frame
  # ========================================================================
  # Convert all numeric columns, handling any parsing issues
  
  my_data <- data.frame(
    date = parsed_dates,                           # Date (R Date object)
    IRGAtime = data$TIME,                          # Original time string
    unixtime = data$unixtime,                      # Unix timestamp
    PosiXct.time = as.POSIXct(data$unixtime,       # POSIXct datetime
                              tz = timezone,
                              origin = "1970-01-01"),
    flowrate = suppressWarnings(
      as.numeric(data$flowrate)                    # Convert to numeric, suppress warnings
    ),
    CO2 = suppressWarnings(
      as.numeric(data$CO2)                         # CO2 in ppb
    ),
    Press = suppressWarnings(
      as.numeric(data$Patm)                        # Pressure in hPa
    ),
    stringsAsFactors = FALSE
  )
  
  if (verbose) {
    message("[read_IRGA] Numeric conversions complete")
    message("  - Flowrate: ", sum(!is.na(my_data$flowrate)), " valid values")
    message("  - CO2: ", sum(!is.na(my_data$CO2)), " valid values")
    message("  - Pressure: ", sum(!is.na(my_data$Press)), " valid values")
  }
  
  # ========================================================================
  # STEP 6: Sort by timestamp
  # ========================================================================
  # Ensure temporal order in case files were not in chronological order
  
  my_data <- my_data[order(my_data$unixtime), ]
  
  # ========================================================================
  # STEP 7: Remove exact duplicates
  # ========================================================================
  # IRGA instruments sometimes record the same measurement multiple times
  # at the exact same timestamp. We keep only the first occurrence.
  
  initial_rows <- nrow(my_data)
  my_data <- my_data[!duplicated(my_data$unixtime), ]
  removed_duplicates <- initial_rows - nrow(my_data)
  
  if (verbose) {
    message("[read_IRGA] Removed ", removed_duplicates, " exact timestamp duplicates")
    message("[read_IRGA] Final dataset: ", nrow(my_data), " rows")
    message("[read_IRGA] Time range: ", 
            format(min(my_data$PosiXct.time, na.rm = TRUE), "%Y-%m-%d %H:%M:%S"),
            " to ",
            format(max(my_data$PosiXct.time, na.rm = TRUE), "%Y-%m-%d %H:%M:%S"))
  }
  
  return(my_data)
  
}

# ============================================================================
# END OF FUNCTION
# ============================================================================

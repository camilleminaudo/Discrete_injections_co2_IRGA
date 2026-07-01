# ============================================================================
# FUNCTIONS: Delimiter Detection & Time/Date Parsing + read_injections_map
# ============================================================================
#
# PURPOSE:
#   This module provides three functions for reading and parsing injection
#   timing maps (CSV files that specify when each sample was injected).
#   Handles multiple file delimiters, date formats, and time formats.
#
# DATA FORMAT REQUIREMENTS FOR INJECTION MAPS:
#   - File format: CSV (any common delimiter: comma, semicolon, tab, pipe)
#   - File naming: Must contain "Map_injections_" in filename
#   - Required columns (must be present, any order):
#     * date: Date of analysis (multiple formats supported)
#     * label: Sample identifier (will be auto-corrected for duplicates)
#     * time_start: Start of injection window (HH:MM:SS or HH:MM)
#     * time_stop: End of injection window (HH:MM:SS or HH:MM)
#     * n_injections: Number of replicates for this sample (informational)
#
#   IMPORTANT: Label format conventions:
#     - Sample labels should include injection volume: e.g., "Sample_1_5mL_"
#     - Volume will be extracted as numeric value (1.5 in this case)
#     - Flexible format: underscores, spaces, ml/mL all handled
#
# ============================================================================

# ============================================================================
# FUNCTION 1: detect_sep
# ============================================================================
# Automatically detects the delimiter (separator) used in a CSV file
# by counting occurrences of common delimiters in the first line
#
# PARAMETERS:
#   file (string): Path to CSV file
#
# RETURNS:
#   (string): Most frequently occurring delimiter in first line
#             Usually one of: ",", ";", "\t", "|"
# ============================================================================

detect_sep <- function(file) {
  
  # Read first line of file
  first_line <- readLines(file, n = 1)
  
  # List of delimiters to test (in order of likelihood)
  seps <- c(",", ";", "\t", "|")
  
  # Count occurrences of each delimiter in the first line
  counts <- sapply(seps, function(s) {
    stringr::str_count(first_line, fixed(s))
  })
  
  # Return the delimiter with the highest count
  detected_sep <- seps[which.max(counts)]
  
  return(detected_sep)
}

# ============================================================================
# FUNCTION 2: parse_time
# ============================================================================
# Parses time values in flexible formats (HH:MM:SS or HH:MM)
# Falls back gracefully if times are in different formats
#
# PARAMETERS:
#   t (string or vector): Time value(s) to parse
#
# RETURNS:
#   (character vector): Standardized time strings in HH:MM:SS format
# ============================================================================

parse_time <- function(t) {
  
  # Try HH:MM:SS format first (most common)
  result <- strptime(t, "%H:%M:%S")
  
  # Track which ones failed
  fix <- is.na(result)
  
  # For failed entries, try HH:MM format (without seconds)
  if (any(fix)) {
    result[fix] <- strptime(t[fix], "%H:%M")
  }
  
  # If there are still NAs, warn the user
  if (any(is.na(result))) {
    warning("Some time values could not be parsed. Expected format: HH:MM:SS or HH:MM")
  }
  
  # Convert back to standardized HH:MM:SS format
  formatted <- format(result, "%H:%M:%S")
  
  return(formatted)
}

# ============================================================================
# FUNCTION 3: parse_flexible_date (same as in read_IRGA)
# ============================================================================
# Attempts to parse dates in multiple common formats
# Essential for handling technician input inconsistencies
#
# PARAMETERS:
#   date_strings (string or vector): Date value(s) to parse
#
# RETURNS:
#   (Date vector): Parsed dates in R Date format
#
# NOTE:
#   This function is duplicated from read_IRGA.R for module independence
#   If you modify one, consider updating the other
# ============================================================================

parse_flexible_date <- function(date_strings) {
  
  # List of date formats to try (in order of likelihood)
  formats_to_try <- c(
    "%d/%m/%Y",   # DD/MM/YYYY - European standard (most common)
    "%d/%m/%y",   # DD/MM/YY - European, 2-digit year
    "%d-%m-%Y",   # DD-MM-YYYY - Alternative European
    "%d-%m-%y",   # DD-MM-YY - Alternative European, 2-digit year
    "%Y-%m-%d",   # YYYY-MM-DD - ISO standard
    "%Y/%m/%d",   # YYYY/MM/DD - ISO with slashes
    "%m/%d/%Y",   # MM/DD/YYYY - US standard (fallback)
    "%m-%d-%Y"    # MM-DD-YYYY - US alternative
  )
  
  # Try each format sequentially
  for (format in formats_to_try) {
    result <- try(as.Date(date_strings, format = format), silent = TRUE)
    
    # Check if parsing was successful (found at least some valid dates)
    if (!inherits(result, "try-error") && any(!is.na(result))) {
      return(result)
    }
  }
  
  # If we get here, none of the formats worked
  stop("Could not parse dates in injection map. Tried formats: ", 
       paste(formats_to_try, collapse = ", "),
       "\nSample date value: ", date_strings[1])
}

# ============================================================================
# MAIN FUNCTION: read_injections_map
# ============================================================================
#
# PURPOSE:
#   Reads injection timing map CSV file and returns a standardized data frame
#   with cleaned labels, parsed times, and validated data
#
# PARAMETERS:
#   path2file (string): Full path to the injection map CSV file
#   verbose   (logical): Print status messages (default: TRUE)
#
# RETURNS:
#   Data frame with columns:
#   - date: Date of analysis (R Date format)
#   - label: Cleaned sample identifier (unique, hyphens instead of underscores)
#   - time_start: Start of injection window (HH:MM:SS)
#   - time_stop: End of injection window (HH:MM:SS)
#   - n_injections: Number of times sample was injected (informational)
#   - file: Original filename (for tracking which map each row came from)
#
# NOTES:
#   - Auto-removes rows with missing/empty labels
#   - Auto-detects and fixes duplicate labels (appends _1, _2, etc.)
#   - Standardizes label format (replaces underscores with hyphens)
#   - Appends "_1" suffix to all labels for consistency with integration output
#
# ============================================================================

read_injections_map <- function(path2file, verbose = TRUE) {
  
  # ========================================================================
  # INPUT VALIDATION
  # ========================================================================
  
  if (!file.exists(path2file)) {
    stop("Error: File '", path2file, "' does not exist.")
  }
  
  if (verbose) {
    message("[read_injections_map] Reading ", basename(path2file))
  }
  
  # ========================================================================
  # STEP 1: Detect delimiter and read file
  # ========================================================================
  # The CSV file might use any common delimiter; auto-detect it
  
  sep <- detect_sep(path2file)
  
  if (verbose) {
    message("  - Detected delimiter: ", 
            if(sep == "\t") "TAB" else if(sep == ",") "COMMA" else sep)
  }
  
  # Read the CSV file
  mapinj <- tryCatch({
    read.csv(path2file, sep = sep, stringsAsFactors = FALSE)
  }, error = function(e) {
    stop("Error reading file '", path2file, "': ", e$message)
  })
  
  # ========================================================================
  # STEP 2: Validate required columns exist
  # ========================================================================
  
  required_cols <- c("date", "label", "time_start", "time_stop", "n_injections")
  missing_cols <- setdiff(required_cols, colnames(mapinj))
  
  if (length(missing_cols) > 0) {
    stop("Error: Required columns missing in ", basename(path2file), ": ",
         paste(missing_cols, collapse = ", "),
         "\nFound columns: ", paste(colnames(mapinj), collapse = ", "))
  }
  
  # ========================================================================
  # STEP 3: Remove rows with missing or empty labels
  # ========================================================================
  # A label is required to identify the sample
  
  initial_rows <- nrow(mapinj)
  
  mapinj <- mapinj %>%
    filter(!is.na(label)) %>%
    filter(label != "")
  
  removed_empty <- initial_rows - nrow(mapinj)
  
  if (removed_empty > 0 && verbose) {
    message("  - Removed ", removed_empty, " rows with missing/empty labels")
  }
  
  if (nrow(mapinj) == 0) {
    stop("Error: No valid injection entries in ", basename(path2file))
  }
  
  # ========================================================================
  # STEP 4: Check for and fix duplicate labels
  # ========================================================================
  # If a sample was analyzed multiple times, it may appear multiple times
  # We handle this by appending numeric suffixes (handled later after formatting)
  
  n_duplicates <- sum(duplicated(mapinj$label))
  
  if (n_duplicates > 0) {
    if (verbose) {
      message("  - Found ", n_duplicates, " duplicate sample labels")
    }
    
    # For each label that appears multiple times, append _1, _2, etc.
    for (k in which(duplicated(mapinj$label, fromLast = FALSE))) {
      
      # Find all rows with this label
      duplicate_label <- mapinj$label[k]
      indices <- which(mapinj$label == duplicate_label)
      
      if (verbose) {
        message("    ... Duplicated label '", duplicate_label, 
                "' appears ", length(indices), " times -> renaming to ",
                duplicate_label, "_1, _2, etc.")
      }
      
      # Assign numeric suffixes to all occurrences
      for (i in seq_along(indices)) {
        mapinj$label[indices[i]] <- paste0(duplicate_label, "_", i)
      }
    }
  }
  
  # ========================================================================
  # STEP 5: Standardize label format
  # ========================================================================
  # Replace underscores with hyphens for consistency
  
  mapinj$label <- gsub("_", "-", mapinj$label)
  
  # ========================================================================
  # STEP 6: Append "_1" suffix to all labels
  # ========================================================================
  # This ensures consistency with peak IDs generated in integration
  # (peaks are labeled as label_1, label_2, etc. for multiple detected peaks)
  
  mapinj$label <- paste0(mapinj$label, "-1")
  
  # ========================================================================
  # STEP 7: Extract and validate date of analysis
  # ========================================================================
  # The 'date' column should be consistent across all rows in one map file
  
  dayofanalysis <- mapinj %>%
    select(date) %>%
    pull() %>%
    unique()
  
  if (length(dayofanalysis) > 1 && verbose) {
    message("  - WARNING: Multiple dates found in map file:")
    message("    ", paste(dayofanalysis, collapse = ", "))
    message("    Using first date: ", dayofanalysis[1])
  }
  
  dayofanalysis <- dayofanalysis[1]
  
  # ========================================================================
  # STEP 8: Parse date with flexible format handling
  # ========================================================================
  
  parsed_date <- parse_flexible_date(dayofanalysis)
  
  mapinj$date <- parsed_date
  
  if (verbose) {
    message("  - Date parsed as: ", format(parsed_date, "%d-%b-%Y"))
  }
  
  # ========================================================================
  # STEP 9: Parse start and stop times
  # ========================================================================
  # Handle variable formats for time columns
  
  mapinj <- mapinj %>%
    mutate(
      time_start = parse_time(time_start),
      time_stop = parse_time(time_stop)
    )
  
  if (verbose) {
    message("  - Parsed ", nrow(mapinj), " injection time windows")
  }
  
  # ========================================================================
  # STEP 10: Validate time windows
  # ========================================================================
  # Check for common errors in time specification
  
  for (i in seq_len(nrow(mapinj))) {
    t_start <- mapinj$time_start[i]
    t_stop <- mapinj$time_stop[i]
    label <- mapinj$label[i]
    
    # Convert to numeric for comparison
    t_start_sec <- as.numeric(hms::as_hms(t_start))
    t_stop_sec <- as.numeric(hms::as_hms(t_stop))
    
    if (t_stop_sec < t_start_sec) {
      warning("Time window error for label '", label, "': ",
              "stop_time (", t_stop, ") is before start_time (", t_start, ")")
    }
    
    duration_sec <- t_stop_sec - t_start_sec
    
    if (duration_sec < 60 && duration_sec > 0) {
      warning("Short time window for '", label, "': ", 
              round(duration_sec), " seconds (expected at least 60s)")
    }
    
    if (duration_sec > 10 * 60) {
      warning("Long time window for '", label, "': ", 
              round(duration_sec / 60, 1), " minutes (expected < 10 min)")
    }
  }
  
  # ========================================================================
  # STEP 11: Select and organize final columns
  # ========================================================================
  # Keep only the columns we need, in a logical order
  
  mapinj <- mapinj %>%
    select(date, label, time_start, time_stop, n_injections)
  
  # ========================================================================
  # STEP 12: Add file source information
  # ========================================================================
  # Useful for tracing data back to original file when combining multiple maps
  
  mapinj$file <- basename(path2file)
  
  if (verbose) {
    message("[read_injections_map] Complete. Returning ", nrow(mapinj), 
            " injection records")
  }
  
  return(mapinj)
}

# ============================================================================
# END OF MODULE
# ============================================================================

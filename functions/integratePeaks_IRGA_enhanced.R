# ============================================================================
# FUNCTION: integratePeaks_IRGA
# ============================================================================
#
# PURPOSE:
#   Detects peaks in IRGA time-series data within specified injection windows,
#   integrates peak areas with baseline correction, calculates statistics,
#   and generates publication-quality integration plots.
#
# DATA REQUIREMENTS:
#   - raw_data: Data frame from read_IRGA() with columns:
#     * unixtime, unixtime_original, CO2 (or other gas column)
#     * Date, time, pressure, flowrate (for reference)
#   - mapinj: Data frame from read_injections_map() with columns:
#     * date, label, time_start, time_stop, n_injections, file
#   - folder_results: Path to results directory (must exist)
#   - folder_plots: Path to plots directory (must exist)
#
# PARAMETERS:
#   raw_data                 (data frame): IRGA time-series data
#   mapinj                   (data frame): Injection timing map
#   secs_diff_REAL_minus_IRGA (numeric): Time correction offset in seconds
#                            (default: 0; use if IRGA clock differs from real time)
#   timezone                 (string): Timezone for time handling (default: "CET")
#   title                    (string): Identifier for output files (e.g., "rawfile_01")
#   minpeakheight_fraction   (numeric): Peak detection threshold as fraction of signal
#                            range (default: 0.2 = 1/5 of range)
#   minpeakdistance_sec      (numeric): Minimum spacing between peaks in seconds
#                            (default: 5)
#   secondsbefore_max        (numeric): Seconds before peak maximum to include
#                            in integration window (default: 4)
#   secondsafter_max         (numeric): Seconds after peak maximum to include
#                            in integration window (default: 7)
#   verbose                  (logical): Print status messages (default: TRUE)
#
# OUTPUTS:
#   1. CSV file: integrated_injections_CO2_[title].csv
#      Columns: dayofanalysis, label, peak_id, peaksum, secondspeak,
#               peak_base, peakmax, unixtime_ofmax, raw_peaksum, peakSNR,
#               avg_remark, sd_remark, n_remark, avg_baseline, sd_nopeak, n_nopeak
#
#   2. PDF file: Integrations_CO2_[title].pdf
#      One plot per sample/injection sequence showing:
#      - Raw signal (dashed line)
#      - Baseline-corrected peaks (points and line)
#      - Peak integration results (points at peak maxima)
#      - Summary statistics (average ± SD, CV)
#
# RETURNS:
#   Invisibly returns the integrated peaks data frame (for optional further processing)
#
# TECHNICAL NOTES:
#   - Peak detection uses local maxima finding with criteria:
#     * At least 1 ascending point before maximum
#     * At least 2 descending points after maximum
#     * Height > minpeakheight_fraction of signal range above Q25 quantile
#     * Minimum spacing of minpeakdistance_sec between peaks
#   - Baseline correction: subtracts first value in integration window from all points
#   - Integration: sums baseline-corrected values across time window
#   - SNR: peak area divided by standard deviation of non-peak signal
#
# ============================================================================

integratePeaks_IRGA <- function(
    raw_data,
    mapinj,
    secs_diff_REAL_minus_IRGA = 0,
    timezone = "CET",
    title = "dummytitle",
    minpeakheight_fraction = 0.2,
    minpeakdistance_sec = 5,
    secondsbefore_max = 4,
    secondsafter_max = 7,
    verbose = TRUE) {
  
  # ========================================================================
  # PARAMETER VALIDATION AND SETUP
  # ========================================================================
  
  if (verbose) {
    message("[integratePeaks_IRGA] Starting peak integration")
    message("  - Title/identifier: ", title)
    message("  - Number of injection records: ", nrow(mapinj))
    message("  - Data rows: ", nrow(raw_data))
  }
  
  # Check that required global variables exist (set by calling script)
  if (!exists("folder_results")) {
    stop("Error: folder_results not defined. ",
         "Check that calling script defines this variable.")
  }
  if (!exists("folder_plots")) {
    stop("Error: folder_plots not defined. ",
         "Check that calling script defines this variable.")
  }
  
  if (!dir.exists(folder_results)) {
    warning("Creating folder_results directory: ", folder_results)
    dir.create(folder_results, showWarnings = FALSE)
  }
  if (!dir.exists(folder_plots)) {
    warning("Creating folder_plots directory: ", folder_plots)
    dir.create(folder_plots, showWarnings = FALSE)
  }
  
  # ========================================================================
  # STEP 1: TIME CORRECTION (if needed)
  # ========================================================================
  # If IRGA clock was incorrect before synchronization, apply offset
  
  if (secs_diff_REAL_minus_IRGA != 0) {
    if (verbose) {
      message("  - Applying time correction: ", secs_diff_REAL_minus_IRGA, " seconds")
    }
    raw_data$unixtime <- raw_data$unixtime_original + secs_diff_REAL_minus_IRGA
  }
  
  # ========================================================================
  # STEP 2: INITIALIZE OUTPUT DATA STRUCTURES
  # ========================================================================
  
  gas <- "CO2"  # Currently hardcoded, could be parameterized for CH4, N2O, etc.
  
  # Data frame to accumulate all integrated peaks
  A <- data.frame(
    dayofanalysis = character(),      # Date of analysis
    label = character(),               # Sample identifier
    peak_id = character(),             # Unique peak identifier (label_1, label_2, etc.)
    peaksum = double(),                # Integrated peak area (baseline-corrected)
    secondspeak = double(),            # Duration of peak (number of measurements)
    peak_base = double(),              # Baseline value at start of integration window
    peakmax = double(),                # Maximum deviation from baseline
    unixtime_ofmax = double(),         # Unix timestamp of peak maximum
    raw_peaksum = double(),            # Integrated raw signal (not baseline-corrected)
    peakSNR = double(),                # Signal-to-noise ratio
    avg_remark = double(),             # Mean signal across entire injection window
    sd_remark = double(),              # Std dev of signal across entire window
    n_remark = double(),               # Number of measurements in window
    avg_baseline = double(),           # Mean signal outside peaks
    sd_nopeak = double(),              # Std dev of signal outside peaks
    n_nopeak = double(),               # Number of measurements outside peaks
    stringsAsFactors = FALSE
  )
  
  # List to store ggplot objects (one per injection sequence)
  plotspeak <- list()
  
  # ========================================================================
  # STEP 3: LOOP OVER INJECTION SEQUENCES
  # ========================================================================
  # Process each labeled sample/injection window
  
  for (inj in mapinj$label) {
    
    if (verbose) {
      message("Processing injection: ", inj)
    }
    
    # ====================================================================
    # STEP 3.1: Get day of analysis and time window bounds
    # ====================================================================
    
    dayofanalysis <- mapinj$date[which(mapinj$label == inj)]
    
    # Convert date + time_start to Unix timestamp
    unixstart <- as.numeric(as.POSIXct(
      paste(mapinj[mapinj$label == inj, ]$date,
            mapinj[mapinj$label == inj, ]$time_start),
      tz = timezone
    ))
    
    # Convert date + time_stop to Unix timestamp
    unixend <- as.numeric(as.POSIXct(
      paste(mapinj[mapinj$label == inj, ]$date,
            mapinj[mapinj$label == inj, ]$time_stop),
      tz = timezone
    ))
    
    # ====================================================================
    # STEP 3.2: Validate time window
    # ====================================================================
    
    if (unixend < unixstart) {
      warning("Time window error for ", inj, ": stop_time < start_time")
      next
    }
    
    duration_sec <- unixend - unixstart
    
    if (duration_sec < 60 && duration_sec > 0) {
      warning("Short time window for ", inj, ": ", round(duration_sec), 
              " seconds (expected >= 60s)")
    }
    
    if (duration_sec > 10 * 60) {
      warning("Long time window for ", inj, ": ", round(duration_sec / 60, 1),
              " minutes (expected <= 10 min)")
    }
    
    # ====================================================================
    # STEP 3.3: Extract data for this injection window
    # ====================================================================
    
    inj_data <- raw_data[between(raw_data$unixtime, unixstart, unixend), ]
    
    if (nrow(inj_data) == 0) {
      warning("No corresponding IRGA data found for ", inj, 
              " in time window ", unixstart, " to ", unixend)
      next
    }
    
    # Add label column for tracking
    inj_data$label <- inj
    
    # ====================================================================
    # STEP 4: PEAK DETECTION
    # ====================================================================
    # Find local maxima in the CO2 signal
    
    if (verbose) {
      message("  - Detecting peaks in signal")
    }
    
    # ====================================================================
    # STEP 4.1: Determine peak height threshold
    # ====================================================================
    # Peaks must be at least minpeakheight_fraction times the signal range above Q25
    
    low_boundary_peak <- inj_data %>%
      summarise(low = quantile(!!sym(gas), 0.25)) %>%
      pull(low) %>%
      as.numeric()
    
    high_boundary_peak <- inj_data %>%
      summarise(high = max(!!sym(gas), na.rm = TRUE)) %>%
      pull(high)
    
    min_peak_height <- ((high_boundary_peak - low_boundary_peak) * 
                          minpeakheight_fraction) + low_boundary_peak
    
    if (verbose) {
      message("    * Signal range: [", round(low_boundary_peak, 1), ", ", 
              round(high_boundary_peak, 1), "]")
      message("    * Peak height threshold: ", round(min_peak_height, 1))
    }
    
    # ====================================================================
    # STEP 4.2: Use pracma::findpeaks to locate local maxima
    # ====================================================================
    
    peaks_matrix <- pracma::findpeaks(
      inj_data[[gas]],
      minpeakheight = min_peak_height,
      nups = 1,                          # Require 1 ascending point before maximum
      ndowns = 2,                        # Require 2 descending points after maximum
      minpeakdistance = minpeakdistance_sec
    )
    
    # ====================================================================
    # STEP 4.3: Mark peak locations in data
    # ====================================================================
    
    inj_data <- inj_data %>%
      mutate(
        is_localmaxgas = ifelse(
          row_number() %in% if(is.null(peaks_matrix)) c() else peaks_matrix[, 2],
          TRUE,
          FALSE
        ),
        peak_id = ifelse(
          is_localmaxgas,
          paste0(label, "_", cumsum(is_localmaxgas)),
          NA
        )
      )
    
    # ====================================================================
    # STEP 5: DEFINE INTEGRATION WINDOWS
    # ====================================================================
    # Spread peak_id to include surrounding points (secondsbefore_max and 
    # secondsafter_max) to ensure we capture the full peak
    
    if (verbose) {
      message("  - Defining integration windows (", secondsbefore_max, 
              " sec before, ", secondsafter_max, " sec after peak)")
    }
    
    inj_data <- inj_data %>%
      mutate(
        peak_id = map_chr(row_number(), function(idx) {
          # For each row, find peak_id in surrounding window
          surrounding_codes <- peak_id[
            seq(max(1, idx - secondsafter_max), 
                min(n(), idx + secondsbefore_max))
          ]
          
          # Return first non-NA peak_id found, or NA if none
          if (any(!is.na(surrounding_codes))) {
            return(first(na.omit(surrounding_codes)))
          } else {
            return(NA)
          }
        })
      )
    
    # ====================================================================
    # STEP 6: CALCULATE BASELINE STATISTICS
    # ====================================================================
    # Characterize signal outside peak windows for SNR calculation
    
    avg_nopeak <- inj_data %>%
      filter(is.na(peak_id)) %>%
      summarise(avg = mean(!!sym(gas), na.rm = TRUE)) %>%
      pull(avg)
    
    sd_nopeak <- inj_data %>%
      filter(is.na(peak_id)) %>%
      summarise(sd = sd(!!sym(gas), na.rm = TRUE)) %>%
      pull(sd)
    
    n_nopeak <- inj_data %>%
      filter(is.na(peak_id)) %>%
      summarise(n = sum(!is.na(!!sym(gas)))) %>%
      pull(n)
    
    # ====================================================================
    # STEP 7: CALCULATE OVERALL INJECTION WINDOW STATISTICS
    # ====================================================================
    
    avg_remark <- inj_data %>%
      summarise(avg = mean(!!sym(gas), na.rm = TRUE)) %>%
      pull(avg)
    
    sd_remark <- inj_data %>%
      summarise(sd = sd(!!sym(gas), na.rm = TRUE)) %>%
      pull(sd)
    
    n_remark <- inj_data %>%
      summarise(n = sum(!is.na(!!sym(gas)))) %>%
      pull(n)
    
    # ====================================================================
    # STEP 8: INTEGRATE DETECTED PEAKS
    # ====================================================================
    # For each peak, calculate area, baseline, max value, and statistics
    
    if (verbose) {
      message("  - Integrating peaks")
    }
    
    integrated <- inj_data %>%
      filter(!is.na(peak_id)) %>%
      group_by(label, peak_id) %>%
      mutate(
        # Baseline correction: subtract first value in peak window
        gas_bc = !!sym(gas) - first(!!sym(gas)),
        # Baseline value at start of window
        peak_base = first(!!sym(gas))
      ) %>%
      summarise(
        # Area: sum of baseline-corrected signal
        peaksum = sum(gas_bc),
        # Store baseline for reference
        peak_base = mean(peak_base, na.rm = TRUE),
        # Duration: number of points in peak
        secondspeak = sum(!is.na(gas_bc)),
        # Maximum deviation from baseline
        peakmax = ifelse(
          all(is.na(gas_bc)),
          NA_real_,
          max(gas_bc, na.rm = TRUE)
        ),
        # Timestamp of maximum
        unixtime_ofmax = ifelse(
          all(is.na(gas_bc)),
          NA_real_,
          first(unixtime[gas_bc == max(gas_bc, na.rm = TRUE)])
        ),
        # Raw signal sum (not baseline-corrected)
        raw_peaksum = sum(!!sym(gas)),
        .groups = "keep"
      ) %>%
      mutate(
        # Add contextual statistics
        dayofanalysis = dayofanalysis,
        peakSNR = peaksum / sd_nopeak,         # Signal-to-noise ratio
        avg_remark = avg_remark,
        sd_remark = sd_remark,
        n_remark = n_remark,
        avg_nopeak = avg_nopeak,
        sd_nopeak = sd_nopeak,
        n_nopeak = n_nopeak
      ) %>%
      ungroup()
    
    # ====================================================================
    # STEP 8.1: Check if peaks were detected
    # ====================================================================
    
    if (nrow(integrated) == 0) {
      warning("No peaks detected for ", inj, ", skipping plot")
      next
    }
    
    # ====================================================================
    # STEP 9: CALCULATE PEAK STATISTICS FOR PLOT ANNOTATION
    # ====================================================================
    
    avg_peaksum <- mean(integrated$peaksum)
    sd_peaksum <- sd(integrated$peaksum)
    
    # ====================================================================
    # STEP 10: PREPARE DATA FOR VISUALIZATION
    # ====================================================================
    # Format peak data with both endpoints for baseline correction visualization
    
    peakdataseries <- inj_data %>%
      filter(!is.na(peak_id)) %>%
      group_by(label, peak_id) %>%
      mutate(
        # Baseline correction: subtract average of first and last points
        gas_bc = !!sym(gas) - ((first(!!sym(gas)) + last(!!sym(gas))) / 2)
      )
    
    # ====================================================================
    # STEP 11: CREATE INTEGRATION PLOT
    # ====================================================================
    
    p <- ggplot() +
      # Layer 1: Raw signal (dashed line)
      geom_line(
        data = inj_data,
        aes(x = as.POSIXct(unixtime, tz = timezone),
            y = !!sym(gas),
            col = "1_raw data"),
        linetype = 2
      ) +
      # Layer 2: Baseline-corrected peaks (points and line)
      geom_point(
        data = subset(peakdataseries, !is.na(peak_id)),
        aes(x = as.POSIXct(unixtime, tz = timezone),
            y = gas_bc,
            col = "2_peaks base corrected")
      ) +
      geom_line(
        data = subset(peakdataseries, !is.na(peak_id)),
        aes(x = as.POSIXct(unixtime, tz = timezone),
            y = gas_bc,
            col = "2_peaks base corrected")
      ) +
      # Layer 3: Peak integration results
      geom_point(
        data = integrated,
        aes(x = as.POSIXct(unixtime_ofmax, tz = timezone),
            y = peaksum,
            col = "3_peak integration"),
        size = 3
      ) +
      # Formatting
      scale_y_continuous(name = paste("Signal", gas)) +
      scale_x_datetime(name = "IRGA time", timezone = timezone) +
      labs(col = "") +
      ggtitle(paste0(format(dayofanalysis, "%d-%b-%Y"), ", injection: ", inj)) +
      theme_bw() +
      # Annotation: summary statistics
      annotate(
        "text",
        x = as.POSIXct(min(integrated$unixtime_ofmax, na.rm = TRUE) - 50, 
                       tz = timezone, origin = "1970-01-01"),
        y = min(integrated$peaksum, na.rm = TRUE) * 0.8,
        label = paste(
          "Avg: ", round(avg_peaksum, 2),
          " ± ", round(sd_peaksum, 2),
          " (CV = ", round(sd_peaksum / avg_peaksum, 2), ")"
        ),
        color = "black",
        hjust = 0,
        vjust = 1,
        size = 4,
        fontface = "italic"
      )
    
    # Store plot for later PDF export
    plotspeak[[inj]] <- p
    
    # ====================================================================
    # STEP 12: Accumulate results
    # ====================================================================
    
    A <- rbind(A, integrated)
    
  }  # End of injection loop
  
  # ========================================================================
  # STEP 13: SAVE RESULTS TO CSV
  # ========================================================================
  
  results_file <- paste0(folder_results, "/", "integrated_injections_", 
                        gas, "_", title, ".csv")
  
  write.csv(A, file = results_file, row.names = FALSE)
  
  if (verbose) {
    message("[integratePeaks_IRGA] Saved integrated peaks to: ", 
            basename(results_file))
    message("  - Rows: ", nrow(A))
  }
  
  # ========================================================================
  # STEP 14: SAVE PLOTS TO PDF
  # ========================================================================
  
  if (length(plotspeak) > 0) {
    
    pdf_file <- paste0(folder_plots, "/Integrations_", gas, "_", title, ".pdf")
    
    pdf(file = pdf_file, width = 10, height = 6)
    
    for (plot_name in names(plotspeak)) {
      print(plotspeak[[plot_name]])
    }
    
    dev.off()
    
    if (verbose) {
      message("[integratePeaks_IRGA] Saved plots to: ", basename(pdf_file))
      message("  - Pages: ", length(plotspeak))
    }
    
  } else {
    warning("No plots generated (no valid peaks detected in any injection)")
  }
  
  if (verbose) {
    message("[integratePeaks_IRGA] Complete")
  }
  
  # Return results invisibly for optional further processing
  invisible(A)
  
}

# ============================================================================
# END OF FUNCTION
# ============================================================================

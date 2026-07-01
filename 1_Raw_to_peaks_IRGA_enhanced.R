# ============================================================================
# SCRIPT 1: Raw IRGA Data to Integrated Peaks
# ============================================================================
#
# PURPOSE:
#   This script reads raw IRGA (Li-COR gas analyzer) data files, imports
#   injection timing maps, detects and integrates peaks with baseline
#   correction, and generates both data outputs and visualization plots.
#
# OUTPUT FILES GENERATED:
#   1. integrated_injections_CO2_[title].csv
#      - Peak areas, baseline values, signal-to-noise ratios for each peak
#   2. Integrations_CO2_[title].pdf
#      - Visual plots showing baseline correction and peak integration
#   3. data_coverage_plot.png (optional)
#      - Shows temporal coverage of raw IRGA measurements
#
# WORKFLOW:
#   1. Load required packages and functions
#   2. Read all raw IRGA data files
#   3. Load injection timing maps
#   4. Visualize data coverage
#   5. Detect and integrate peaks
#   6. Save results and plots
#
# REQUIRED DATA STRUCTURE:
#   See IRGA_PIPELINE_README.md for detailed data format specifications
#
# ============================================================================

# Clean Global environment
rm(list = ls())

# ============================================================================
# SECTION 1: CONFIGURE DIRECTORIES
# ============================================================================
# Set up paths to your project folders. Adjust the project_root path to 
# point to your actual data location.

# Option A: Use test/example project
# project_root <- paste0(dirname(rstudioapi::getSourceEditorContext()$path), 
#                        "/EXAMPLE_PROJECT")

# Option B: Use your own data (UNCOMMENT and edit this line)
project_root <- "C:/Users/Camille Minaudo/OneDrive - Universitat de Barcelona/Documentos/PROJECTS/2026_DRYINGLAKE/data/DIC_smallVolumes_tests/IRGA/DILUSIONES_SOBREPRESION/"

# ========================================================================
# VALIDATE PROJECT ROOT
# ========================================================================

if (!dir.exists(project_root)) {
  stop("ERROR: project_root directory does not exist: ", project_root,
       "\nPlease edit the project_root variable above to point to your data folder.")
}

message("[Script 1] Project root: ", project_root)

# ========================================================================
# DEFINE DATA FOLDERS
# ========================================================================

folder_raw <- paste0(project_root, "/Rawdata")
# ^ Contains raw IRGA CSV files exported directly from the instrument

folder_mapinjections <- paste0(project_root, "/Map_injections")
# ^ Contains CSV files with injection timing information
#   (files must be named with "Map_injections_" prefix)

folder_plots <- paste0(project_root, "/Integration_plots")
# ^ Output folder for PDF plots of peak integration
if (!dir.exists(folder_plots)) {
  dir.create(folder_plots)
  message("Created plots folder: ", folder_plots)
}

folder_results <- paste0(project_root, "/Results_ppm")
# ^ Output folder for CSV files with integrated peak data
if (!dir.exists(folder_results)) {
  dir.create(folder_results)
  message("Created results folder: ", folder_results)
}

# Validate that input folders exist
if (!dir.exists(folder_raw)) {
  stop("ERROR: Rawdata folder not found: ", folder_raw)
}
if (!dir.exists(folder_mapinjections)) {
  stop("ERROR: Map_injections folder not found: ", folder_mapinjections)
}

# ============================================================================
# SECTION 2: LOAD REQUIRED PACKAGES
# ============================================================================
# Install (if needed) and load all dependencies

required_pkgs <- c(
  "tidyverse",      # Data manipulation (dplyr, tidyr, ggplot2, etc.)
  "readxl",         # Excel file reading (if calibration files are in Excel)
  "lubridate",      # Date/time handling
  "pracma",         # Peak detection (findpeaks function)
  "stringr",        # String manipulation
  "ggpmisc"         # ggplot extensions
)

for (pkg in required_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message("Installing package: ", pkg)
    install.packages(pkg)
  }
  library(pkg, character.only = TRUE)
}

message("[Script 1] All required packages loaded successfully")

# ============================================================================
# SECTION 3: LOAD CUSTOM FUNCTIONS
# ============================================================================
# Source the enhanced function definitions

# Get the directory where this script is located
repo_root <- dirname(rstudioapi::getSourceEditorContext()$path)

# Build path to functions folder
functions_path <- paste0(repo_root, "/functions")

if (!dir.exists(functions_path)) {
  stop("ERROR: Functions folder not found at ", functions_path,
       "\nMake sure all function files are in a 'functions' subfolder")
}

# Source all R files in the functions folder
files_sources <- list.files(path = functions_path, 
                            pattern = "\\.R$", 
                            full.names = TRUE)

if (length(files_sources) == 0) {
  stop("ERROR: No function files found in ", functions_path)
}

message("[Script 1] Loading functions from: ", functions_path)
for (f in files_sources) {
  message("  - Loading: ", basename(f))
  source(f)
}

# ============================================================================
# SECTION 4: READ RAW IRGA DATA
# ============================================================================
# This step reads all raw IRGA CSV files, combines them, and creates
# a time-series data frame with standardized columns.

message("\n[Script 1] ========== STEP 1: Import Raw IRGA Data ==========")

# Get list of files
rawfiles <- list.files(path = folder_raw)
message("Found ", length(rawfiles), " file(s) in Rawdata folder")

# Read and combine all raw data files
# The read_IRGA() function handles:
# - Multiple file formats
# - Flexible date format parsing
# - Time parsing (HH:MM:SS and HH:MM)
# - Duplicate removal
# - Sorting by timestamp

raw_data <- read_IRGA(
  myfolder = folder_raw,
  timezone = "CET",      # Adjust if your instrument uses different timezone
  verbose = TRUE
)

# Store original unixtime (before any corrections)
raw_data$unixtime_original <- raw_data$unixtime

# Remove consecutive duplicates within the same IRGA recorded time
# (IRGA sometimes records the same time value multiple times)
raw_data <- raw_data %>%
  group_by(IRGAtime) %>%
  summarise(across(everything(), ~last(.))) %>%
  ungroup()

if (nrow(raw_data) == 0) {
  stop("ERROR: No valid data after processing. Check your raw files.")
}

message("[Script 1] Raw data summary:")
message("  - Rows retained: ", nrow(raw_data))
message("  - Date range: ", 
        format(min(raw_data$date, na.rm = TRUE), "%d-%b-%Y"), " to ",
        format(max(raw_data$date, na.rm = TRUE), "%d-%b-%Y"))
message("  - Time range: ",
        format(min(raw_data$PosiXct.time, na.rm = TRUE), "%H:%M:%S"), " to ",
        format(max(raw_data$PosiXct.time, na.rm = TRUE), "%H:%M:%S"))

# Add a formatted time column for convenient access
raw_data$timeonly <- format(raw_data$PosiXct.time, format = "%H:%M:%S")

# ============================================================================
# SECTION 5: VISUALIZE DATA COVERAGE
# ============================================================================
# Create a plot showing when measurements were recorded throughout the day
# This helps verify that injection time windows match actual data

message("\n[Script 1] ========== STEP 2: Analyze Data Coverage ==========")

# Bin data by 1-minute intervals to see temporal coverage
binned <- raw_data %>%
  mutate(
    date = as.Date(date),
    # Convert time to seconds since midnight
    time_seconds = as.numeric(hms::as_hms(timeonly)),
    # Bin to 1-minute intervals
    time_bin = floor(time_seconds / 60) * 60
  ) %>%
  distinct(date, time_bin)

# Create coverage visualization
plt <- ggplot(binned, aes(x = time_bin, y = factor(date))) +
  geom_tile(aes(width = 60, height = 0.8), fill = "steelblue") +
  scale_x_continuous(
    name = "Time of day",
    breaks = seq(0, 86400, by = 3600),
    labels = function(s) format(hms::as_hms(s), "%H:%M")
  ) +
  labs(
    title = "IRGA Data Coverage by Time of Day",
    subtitle = "Blue bars show presence of measurements",
    y = "Date"
  ) +
  theme_bw(base_size = 13) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

message("[Script 1] Data coverage plot created")
print(plt)

# ============================================================================
# SECTION 6: READ INJECTION TIMING MAPS
# ============================================================================
# Import CSV files that specify when each sample was injected

message("\n[Script 1] ========== STEP 3: Read Injection Maps ==========")

# Get list of injection map files
maps_available <- list.files(
  path = folder_mapinjections,
  pattern = "\\.csv$",
  ignore.case = TRUE
)

if (length(maps_available) == 0) {
  stop("ERROR: No CSV files found in Map_injections folder: ",
       folder_mapinjections)
}

message("[Script 1] Found ", length(maps_available), " injection map file(s)")

# Read and combine all injection maps
mapinj <- NULL

for (f in maps_available) {
  message("  Reading: ", f)
  
  map_data <- read_injections_map(
    path2file = paste0(folder_mapinjections, "/", f),
    verbose = TRUE
  )
  
  mapinj <- rbind(mapinj, map_data)
}

if (is.null(mapinj) || nrow(mapinj) == 0) {
  stop("ERROR: No injection records could be read from map files")
}

message("[Script 1] Total injection records: ", nrow(mapinj))

# ========================================================================
# Prepare injection data for visualization
# ========================================================================

mapinj_prep <- mapinj %>%
  mutate(
    date = as.Date(date),
    # Calculate midpoint of injection window for plotting
    x_mid = (as.numeric(hms::as_hms(time_start)) + 
             as.numeric(hms::as_hms(time_stop))) / 2
  )

# ============================================================================
# SECTION 7: OVERLAY INJECTION TIMES ON DATA COVERAGE PLOT
# ============================================================================
# Shows where injections occur relative to actual measurements

message("[Script 1] Overlaying injection times on coverage plot...")

plt_with_injections <- plt +
  geom_point(
    data = mapinj_prep,
    aes(x = x_mid, y = factor(date)),
    color = "red",
    size = 3,
    shape = 17
  ) +
  annotate(
    "text",
    x = 86400, y = Inf,
    label = "Red triangles = injection times",
    hjust = 1.02, vjust = 1.5,
    size = 3, color = "red"
  )

print(plt_with_injections)

message("[Script 1] Review the plot above:")
message("  - Blue bars: actual IRGA measurements")
message("  - Red triangles: injection time windows")
message("  - If triangles don't align with bars, check your time windows")

# ============================================================================
# SECTION 8: EXTRACT AND INTEGRATE PEAKS FOR EACH INJECTION MAP
# ============================================================================
# Loop over each injection map file and process all injections

message("\n[Script 1] ========== STEP 4: Extract & Integrate Peaks ==========")

for (f in maps_available) {
  
  message("\n[Script 1] Processing file: ", f)
  
  # Select injection records from this map file
  mapinj_sel <- mapinj[mapinj$file == f, ]
  
  # Extract title (filename without prefix and extension)
  mytitle <- gsub(pattern = "Map_injections_", replacement = "", x = f)
  mytitle <- gsub(pattern = ".csv|.CSV", replacement = "", x = mytitle)
  
  # ====================================================================
  # Call the peak integration function
  # ====================================================================
  # This is where the actual peak detection and integration happens
  
  result <- integratePeaks_IRGA(
    raw_data = raw_data,
    mapinj = mapinj_sel,
    # TIME CORRECTION (if needed)
    # If IRGA clock was wrong before sync, use: secs_diff_REAL_minus_IRGA = -274309
    # (example: IRGA was 274309 seconds slow)
    secs_diff_REAL_minus_IRGA = 0,
    timezone = "CET",
    title = mytitle,
    # PEAK DETECTION PARAMETERS (adjust if peaks aren't detected well)
    minpeakheight_fraction = 0.2,  # Peaks must be > 1/5 of signal range
    minpeakdistance_sec = 5,        # Peaks must be >= 5 seconds apart
    # INTEGRATION WINDOW PARAMETERS (adjust if peaks are cut off)
    secondsbefore_max = 4,          # Include 4 sec before peak maximum
    secondsafter_max = 7,           # Include 7 sec after peak maximum
    verbose = TRUE
  )
  
  # Print any warnings that occurred during this file's processing
  if (length(warnings()) > 0) {
    message("[Script 1] Warnings from this file:")
    print(warnings())
  }
  
}

message("\n[Script 1] ========== COMPLETE ==========")
message("Output files saved to:")
message("  - Plots: ", folder_plots)
message("  - Data: ", folder_results)
message("\nNext step: Run Script 2 (2_Peaks_to_ppm.R) to convert to ppm values")

# ============================================================================
# END OF SCRIPT 1
# ============================================================================

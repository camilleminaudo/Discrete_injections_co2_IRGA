# IRGA Gas Analyzer Data Processing Pipeline - User Guide

## Overview
This pipeline processes discrete sample injections from a high-frequency gas analyzer with an "open-loop" configuration. It extracts discrete 1 mL injections in a baseline carrier, characterizes peaks, calculates peak areas, and transforms them to ppm estimates for each injection.

---

## Pipeline Structure

### Step 1: Raw Data Import & Peak Integration
**Script:** `1_Raw_to_peaks_IRGA_per-peakbasecorrection.R`
- Reads raw IRGA data files from your Rawdata folder
- Imports injection timing maps
- Integrates peaks using baseline correction
- Outputs: Integrated peak areas with statistics

### Step 2: Peak Areas to ppm Conversion
**Script:** `2_Peaks_to_ppm.R`
- Converts integrated peak areas to ppm using calibration factors
- Applies baseline corrections
- Outputs: Calibrated ppm values for each injection

### Step 3: Summary Statistics
**Script:** `3_Summary_of_samples_IRGA.R`
- Compiles all ppm values across samples and dates
- Calculates statistics with optional CV-based injection filtering
- Outputs: Summary tables with mean, SD, and count per sample

---

## Data Format Requirements

### 1. RAW IRGA DATA FILES
**Location:** `[project_root]/Rawdata/`
**Format:** CSV files exported directly from Li-COR IRGA
**Required Columns (first 8 columns):**
1. **Column 1:** Data format identifier (must start with "M")
2. **Column 2:** DATE - Date of measurement
3. **Column 3:** TIME - Time of measurement
4. **Column 4:** Plot number / Sample identifier
5. **Column 5:** Timestamp (can be ignored if DATE+TIME are present)
6. **Column 6:** CO2 concentration (ppb)
7. **Column 7:** Atmospheric pressure (hPa)
8. **Column 8:** Flow rate (µmol/mol)

**Date & Time Format Flexibility:**
- The pipeline now automatically detects and handles multiple date/time formats:
  - Dates: `DD/MM/YYYY`, `DD/MM/YY`, `DD-MM-YYYY`, `DD-MM-YY`, `YYYY-MM-DD`
  - Times: `HH:MM:SS`, `HH:MM`
- **Important:** Make sure all raw files for a single analysis use CONSISTENT date formats

**Example CSV Structure:**
```
M,25/01/2024,10:30:45,Plot1,ignored,485.2,1013.25,500
M,25/01/2024,10:30:46,Plot1,ignored,486.1,1013.25,500
M,25/01/2024,10:30:47,Plot1,ignored,487.3,1013.25,500
```

---

### 2. INJECTION TIMING MAP
**Location:** `[project_root]/Map_injections/`
**Naming Convention:** `Map_injections_[rawfile_identifier].csv` (must include "Map_injections_" prefix)
**Format:** CSV (comma, semicolon, tab, or pipe-delimited - auto-detected)
**Required Columns:**
- **date:** Date of analysis (multiple formats supported, see above)
- **label:** Sample identifier (e.g., "Sample_1", "std_001")
  - Labels will be auto-corrected: duplicates get numbered suffixes
  - Underscores converted to hyphens for consistency
  - Final format: `label_1`, `label_2`, etc.
- **time_start:** Start time of injection window (HH:MM:SS or HH:MM)
- **time_stop:** Stop time of injection window (HH:MM:SS or HH:MM)
- **n_injections:** Number of times this sample was injected

**Example CSV Structure:**
```
date,label,time_start,time_stop,n_injections
25/01/2024,Sample_1,10:30:00,10:31:30,1
25/01/2024,Sample_2,10:35:00,10:36:30,1
25/01/2024,Sample_3,10:40:00,10:41:30,1
```

**Special Notes on Labels:**
- Labels must reflect the injection volume in the format: `SampleName_VolumeInMl_` (e.g., `Std_1_5mL_` means 1.5 mL injected)
  - This is parsed in Step 2 to calculate volume-normalized ppm
  - Example: `Sample_A_1_0mL_` → identifies 1.0 mL injection
  - Flexible format: the script extracts all numeric values, so `Sample_1mL`, `Sample_1ml`, `Sample_-_1.0mL_` all work

---

### 3. FOLDER STRUCTURE

```
project_root/
├── Rawdata/                      [Your raw IRGA CSV files here]
├── Map_injections/               [Your injection timing maps here]
├── functions/                    [Contains all R functions]
│   ├── read_IRGA.R
│   ├── read_injections_map.R
│   ├── integratePeaks_IRGA.R
│   └── [other function files]
├── Integration_plots/            [OUTPUT: PDF plots of each peak integration]
├── Results_ppm/                  [OUTPUT: Converted ppm values]
└── calibration/                  [Calibration files if used]
```

---

## Common Issues & Solutions

### Issue 1: "Error in as.Date(): character string is not in standard unambiguous format"
**Cause:** Date format not recognized
**Solution:** 
- Check that your date column uses consistent format (e.g., all DD/MM/YYYY, not mixed with DD/MM/YY)
- Review the date values in your Map_injections CSV file
- The pipeline will try multiple formats automatically, but consistency helps

### Issue 2: "No corresponding IRGA data for [label]"
**Cause:** Time window in Map_injections doesn't match actual data timestamps
**Solution:**
- Verify that time_start and time_stop in the CSV bracket actual measurements
- Check for timezone mismatches
- Review the data coverage plot generated in Step 1

### Issue 3: "Duplicated label name" - auto-renamed to `label_1`, `label_2`, etc.
**Cause:** Same sample injected multiple times (normal for replicates)
**Solution:** 
- This is expected and handled automatically
- Each replicate injection gets a unique numeric suffix
- Check output to ensure you have the expected number of replicates

### Issue 4: Labels have underscores replaced with hyphens
**Cause:** Underscore standardization for consistency
**Solution:**
- This is automatic. Your original label "Sample_A_Std" becomes "Sample-A-Std"
- The volume extraction still works: "Sample_1mL_" → "Sample-1mL-" (volume extracted as 1.0)

### Issue 5: "Only N valid measurements, returning all" warning
**Cause:** Sample has fewer than 3 injection replicates
**Solution:**
- In Step 3, samples with <3 replicates cannot use CV-based filtering
- The script reports how many injections were used for each sample's mean
- This is normal if you deliberately injected fewer replicates for some samples

---

## Customization Parameters

### In `1_Raw_to_peaks_IRGA_per-peakbasecorrection.R`:
- **secs_diff_REAL_minus_IRGA:** Time correction offset (default 0; use if IRGA clock is off)
- Peak detection parameters (in `integratePeaks_IRGA()`):
  - `minpeakheight`: Fraction of signal range to detect peaks (default: 1/5 of max-Q25 range)
  - `nups`: Number of ascending points required for peak detection (default: 1)
  - `ndowns`: Number of descending points required (default: 2)
  - `minpeakdistance`: Minimum spacing between peaks in seconds (default: 5)

### In `2_Peaks_to_ppm.R`:
- **factor:** Calibration factor (default: 1; replace with your instrument's factor)

### In `3_Summary_of_samples_IRGA.R`:
- **n:** Number of best injections to use for CV-based filtering (default: 3)
- **cv_threshold:** CV improvement threshold for deciding to discard injections

---

## Output Files

### From Step 1 (Raw → Peaks):
- **integrated_injections_CO2_[rawfile_id].csv**
  - Peak areas, baseline values, signal-to-noise ratios
  - One row per detected peak

- **Integrations_CO2_[rawfile_id].pdf**
  - Visual confirmation plots showing baseline correction and peak areas
  - Includes coefficient of variation (CV) for each injection sequence

### From Step 2 (Peaks → ppm):
- **ppm_samples_CO2_[rawfile_id].csv**
  - Volume-normalized ppm values for each injection
  - Columns: dayofanalysis, gas, sample, ml_injected, peak_id, ppm, peaksum, peak_baseppm, unixtime_ofmax, datetime

### From Step 3 (Summary):
- **All_Summary_co2_allinjections.csv**
  - Mean, SD, and count for each sample using all injections
  
- **All_Summary_co2_best3inj.csv**
  - Mean, SD, and count for each sample using only best 3 injections (if CV improves)
  
- **All_Injections_ppm_co2.csv**
  - Individual ppm values for every injection (raw data for further analysis)

---

## Running the Pipeline

1. **Prepare your data:**
   - Export raw IRGA files to `[project_root]/Rawdata/`
   - Create injection timing maps in `[project_root]/Map_injections/`

2. **Run Step 1:**
   ```R
   source("1_Raw_to_peaks_IRGA_per-peakbasecorrection.R")
   ```
   - Review the generated data coverage plot
   - Check integration PDFs to verify peak detection is working
   - Proceed to Step 2 only if peaks look reasonable

3. **Run Step 2:**
   ```R
   source("2_Peaks_to_ppm.R")
   ```
   - Verify output ppm values are in expected range (typically 0–1000 ppm for CO2)
   - Check for warnings about negative baselines

4. **Run Step 3:**
   ```R
   source("3_Summary_of_samples_IRGA.R")
   ```
   - Review summary tables for any unexpected patterns
   - n_discarded > 0 means CV-based filtering occurred

---

## Technical Notes

### Timezone Handling
- All timestamps are converted to and stored in CET (Central European Time)
- Adjust the timezone parameter in functions if your instrument uses a different timezone

### Peak Integration Method
- Uses baseline correction (peak value minus baseline at start of window)
- Baseline defined as first measurement in the integration window
- Peak areas are summed over all data points within the time window
- Baseline signal-to-noise ratio calculated as: peaksum / sd_nopeak

### Calibration
- Currently uses a single point calibration factor
- Ensure your calibration standard is treated identically to samples
- Factor should be determined from standard injection following Li-COR protocols

---

## Support & Troubleshooting

If you encounter unexpected behavior:
1. Check that dates in your Map_injections file are **exactly as written** in your raw IRGA files
2. Verify that time windows in Map_injections actually contain measurement data
3. Review the generated plots and data coverage chart to diagnose timing issues
4. Check for warnings/messages printed during execution

---

## Version History
- v2.0 (2025): Added date format flexibility, extensive documentation, improved error handling
- v1.0 (2024): Initial pipeline release

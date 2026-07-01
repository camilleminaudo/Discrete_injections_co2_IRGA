# IRGA Pipeline - Quick Start Guide

## For the Impatient: Get Started in 5 Minutes

### Step 1: Organize Your Folder Structure

```
your_project_folder/
├── Rawdata/                    ← Put your raw IRGA CSV files here
├── Map_injections/             ← Put your injection timing CSVs here
├── functions/                  ← Put all the R function files here
│   ├── read_IRGA.R
│   ├── read_injections_map.R
│   └── integratePeaks_IRGA.R
├── 1_Raw_to_peaks_IRGA.R      ← Processing script #1
├── 2_Peaks_to_ppm.R            ← Processing script #2
├── 3_Summary_of_samples_IRGA.R ← Processing script #3
└── IRGA_PIPELINE_README.md     ← Full documentation
```

### Step 2: Prepare Your Data

**Injection Map CSV (e.g., `Map_injections_experiment_001.csv`):**
```
date,label,time_start,time_stop,n_injections
25/01/2024,Sample-1-0mL,10:30:00,10:31:30,1
25/01/2024,Sample-2-0-5mL,10:35:00,10:36:30,1
25/01/2024,Std-1-0mL,10:40:00,10:41:30,1
```

**Key Points:**
- `date`: Can be DD/MM/YYYY, DD/MM/YY, DD-MM-YYYY, YYYY-MM-DD, etc.
- `time_start/time_stop`: Can be HH:MM:SS or just HH:MM
- `label`: Should include your injection volume (extracted automatically)
- File name MUST include "Map_injections_"

### Step 3: Edit Script 1

```R
# Open: 1_Raw_to_peaks_IRGA.R
# Find this line (around line 13):
project_root <- "C:/Users/Camille Minaudo/OneDrive - Universitat de Barcelona/Documentos/PROJECTS/2026_DRYINGLAKE/data/DIC_smallVolumes_tests/IRGA/DILUSIONES_SOBREPRESION/"

# Replace with YOUR folder path:
project_root <- "C:/path/to/your_project_folder"

# Save the file
```

### Step 4: Run the Three Scripts in Order

**In RStudio:**

```R
# Script 1: Raw → Peaks
source("1_Raw_to_peaks_IRGA.R")
# Wait for it to finish. Check the plots PDF to verify peaks look good.

# Script 2: Peaks → ppm
source("2_Peaks_to_ppm.R")
# Checks that ppm values are in reasonable range

# Script 3: Summary statistics
source("3_Summary_of_samples_IRGA.R")
# Creates final summary tables
```

### Step 5: Find Your Results

Check the `Results_ppm/` folder:
- `integrated_injections_CO2_*.csv` - Raw peak data (from Script 1)
- `ppm_samples_CO2_*.csv` - Calibrated ppm values (from Script 2)
- `All_Summary_co2_allinjections.csv` - Summary table (from Script 3)
- `Integrations_CO2_*.pdf` - Plots showing peak detection (from Script 1)

---

## Troubleshooting: Most Common Issues

### Issue: "Error: Folder does not exist"
**Solution:** Check that `project_root` path in Script 1 matches YOUR folder path. Use `File → Recent Files` to find it.

### Issue: "No peaks detected"
**Solution:** 
1. Open the `Integrations_CO2_*.pdf` file - do you see signal?
2. If yes, peaks might be too small. Try reducing `minpeakheight_fraction = 0.1` in Script 1 line ~135
3. If no signal in plot, check that injection times overlap with actual measurements

### Issue: "No corresponding IRGA data for [sample]"
**Solution:**
1. Run Script 1 and look at the data coverage plot
2. Red triangles = your injection times
3. Blue bars = actual measurements
4. If they don't overlap, adjust `time_start`/`time_stop` in your injection map

### Issue: "ppm values are negative or too large"
**Solution:** 
1. Check Script 2 - find `factor_CO2 <- 1`
2. Replace with your instrument's actual calibration factor
3. Example: if factor should be 0.5, use `factor_CO2 <- 0.5`

---

## What Each Script Does (60-Second Version)

### Script 1: Raw → Peaks ⚙️
- Reads raw IRGA CSV files
- Reads injection timing maps
- Detects peaks automatically
- Integrates peak areas with baseline correction
- **Creates:** integrated_injections CSV + visualization PDFs

### Script 2: Peaks → ppm 📊
- Takes integrated peak areas
- Divides by volume injected + calibration factor
- Adds baseline concentration
- **Creates:** ppm_samples CSV

### Script 3: Summary 📈
- Compiles all ppm data
- Calculates mean ± SD for each sample
- Optional: uses best 3 injections if it improves precision
- **Creates:** Summary CSV files

---

## Important Parameters (If You Need to Tune)

### Peak Detection Sensitivity (Script 1, ~line 135)

```R
integratePeaks_IRGA(
  ...
  minpeakheight_fraction = 0.2,    # 0.1 = more sensitive, 0.3 = less sensitive
  minpeakdistance_sec = 5          # 3 = closer peaks OK, 10 = peaks far apart
)
```

### Calibration Factor (Script 2, ~line 40)

```R
factor_CO2 <- 1                     # Replace 1 with YOUR calibration value
# Get this from your Li-COR documentation or calculate:
# factor = measured_peaksum / (expected_ppm * volume_injected)
```

### Injection Window Width (Script 1, ~line 138)

```R
integratePeaks_IRGA(
  ...
  secondsbefore_max = 4,            # seconds before peak to include
  secondsafter_max = 7              # seconds after peak to include
)
```

---

## Example: Complete Workflow (10 minutes)

### You have:
- Raw IRGA files in: `C:/data/IRGA_exp/Rawdata/`
- Injection map: `C:/data/IRGA_exp/Map_injections/Map_injections_exp1.csv`
- Li-COR calibration factor: 0.85

### Do this:

```R
# 1. SETUP
setwd("C:/data/IRGA_exp")

# Edit Script 1:
# Change: project_root <- "C:/data/IRGA_exp"

# Edit Script 2:
# Change: factor_CO2 <- 0.85

# 2. RUN SCRIPTS (in order)
source("1_Raw_to_peaks_IRGA.R")     # ~30 sec
# Review the plots - do peaks look right? Yes? Continue.

source("2_Peaks_to_ppm.R")           # ~5 sec
# Check console - are ppm values in reasonable range? (typically 0-1000)

source("3_Summary_of_samples_IRGA.R") # ~5 sec
# Done!

# 3. CHECK RESULTS
dir("Results_ppm")  # See output files
# Open: All_Summary_co2_best3inj.csv in Excel/spreadsheet app
# Your results are ready!
```

---

## Data Format Quick Reference

### Raw IRGA CSV Format
```
M,25/01/2024,10:30:45,Plot1,ignored,485.2,1013.25,500
M,25/01/2024,10:30:46,Plot1,ignored,486.1,1013.25,500
  ↑        ↑          ↑      ↑     ↑       ↑        ↑
  Format   Date       Time   ID    Unused  CO2(ppb) Pressure Flowrate
```

### Injection Map CSV Format
```
date,label,time_start,time_stop,n_injections
25/01/2024,Sample-1-0mL,10:30:00,10:31:30,1
           ↑               ↑        ↑        ↑
           Must have       Must     Must     Informational
           date            include  include  (# of reps)
           in label        volume   times
```

---

## Common Workflow Variations

### Variation 1: Multiple Calibration Runs Per Day
- Run Script 1 normally (all data at once)
- Create separate injection maps for each subset
- Run Scripts 2&3 on each subset

### Variation 2: Multiple Gases (CH4, N2O, CO2)
- Currently scripts are set up for CO2
- To handle multiple gases:
  - Create separate integrated files per gas
  - Create separate ppm files per gas
  - Modify Script 3 to import multiple gases
  - (Contact developer for multi-gas version)

### Variation 3: Batch Processing Multiple Experiments
```R
# Process multiple experiments at once:
experiments <- c("exp1", "exp2", "exp3")

for (exp in experiments) {
  project_root <- paste0("C:/data/", exp)
  source("1_Raw_to_peaks_IRGA.R")
  source("2_Peaks_to_ppm.R")
  source("3_Summary_of_samples_IRGA.R")
}
```

---

## Tips & Tricks

### Tip 1: Check Your Data Quickly
```R
# Before running full pipeline:
raw_data <- read_IRGA("C:/your/Rawdata/folder")
summary(raw_data)  # See date range, CO2 values, etc.
```

### Tip 2: Preview Peak Detection
```R
# After Script 1, review the PDF:
# - Are peaks sharp and isolated?
# - Are they missing? Reduce minpeakheight_fraction
# - Are there false peaks? Increase it
# - Adjust and re-run Script 1
```

### Tip 3: Track Your Calibration
```R
# Keep a log of calibration factors:
# Date        Instrument    Factor
# 2024-01-15  Li-COR#123    0.85
# 2024-02-01  Li-COR#123    0.84  (slight drift)
# Update Script 2 accordingly
```

### Tip 4: Export Summary to Excel
```R
# In R, after Script 3:
# In Excel:
# File → Open → Results_ppm/All_Summary_co2_best3inj.csv
# Now you can format, add notes, make plots
```

---

## If Something Goes Wrong

### Step 1: Read the Console Output
- Look for [Script X] or [function_name] messages
- Red error messages = critical problem
- Yellow warning messages = potential issue but might be OK

### Step 2: Check Your Data
- Does `C:/your/project/Rawdata/` exist with CSV files?
- Does `C:/your/project/Map_injections/` exist with CSV files?
- Do the CSVs have the expected columns?

### Step 3: Simplify to Diagnose
```R
# Test just the import functions:
raw_data <- read_IRGA("C:/your/Rawdata/", verbose = TRUE)
# Did this work? Good, move to next step.

mapinj <- read_injections_map("C:/your/Map_injections/file.csv", verbose = TRUE)
# Did this work? Good, probably an issue in the integration step.
```

### Step 4: Ask for Help
If stuck, provide:
1. Screenshot of error message
2. Sample of your data (first few rows of each CSV)
3. Output from console (copy-paste the [Script X] messages)
4. What you tried so far

---

## Next Steps After Getting Results

1. **Quality Control**
   - Open Integrations_CO2_*.pdf - do peaks look right?
   - Open All_Injections_ppm_co2.csv - any unreasonable values?
   - Check n_discarded column - any samples missing injections?

2. **Analysis**
   - Open All_Summary_co2_best3inj.csv in Excel
   - Plot results, calculate differences, run statistical tests
   - Reference individual injection data if needed

3. **Future Runs**
   - Update calibration factor if instrument drifted
   - Adjust peak detection if conditions changed
   - Keep notes on what works for your samples

---

## FAQ

**Q: Can I run just one script?**
A: No, they're meant to be run in order (1→2→3). Scripts 2 & 3 need output from previous steps.

**Q: What if I only want CO2?**
A: Good news - scripts are already set up for CO2 only. Multi-gas support is available upon request.

**Q: Can I re-run Script 2 with a different calibration factor?**
A: Yes! Just edit `factor_CO2` and re-run Script 2. It will overwrite the previous ppm files.

**Q: How long does each script take?**
A: Typically: Script 1 = 30-60 sec, Script 2 = 5 sec, Script 3 = 5 sec. Depends on data size.

**Q: What if dates in my CSVs are DD-MM-YYYY but I want DD/MM/YYYY?**
A: No need to change anything! The enhanced pipeline handles both automatically.

**Q: Can I use this with older data?**
A: Yes! The enhanced code is backward-compatible. Your existing data formats still work.

---

**Still stuck?** Refer to the full documentation: `IRGA_PIPELINE_README.md`

**Ready to dig deeper?** Check the inline comments in each R file - they explain every step!

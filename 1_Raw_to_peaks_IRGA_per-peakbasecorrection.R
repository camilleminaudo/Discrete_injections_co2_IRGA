#Raw to integrated peaks and baselines#

#Before to run this script, you must run "Map_injections.R" script and manually create the "corrected_XXX_map_injection..." files from the "raw_xxx_map_injection..." within the Map_injections folder. You can copy directly the 'time_start', 'time_stop' and 'label' from the raw_mapinjection OR edit if you have something to change. You also need to specify in 'firstIRGA_TG10_or_TG20' instrument was connected upstream (i.e. first in receiving the injected sample): options are "TG20" (for IRGAN2O first) OR "TG10" (for IRGACH4&CO2 first).This info is used to set the width of integration windows according to the upstream-downstream position of the IRGAs. #For data in "EXAMPLE_PROJECT" folder, TG10 was the first IRGA Upstream. 

#IMPORTANT: Make sure the separator of the csv file (comma [,] separated values) is not changed when you modify the files. Excell might swap separator from comma to semicolon depending on your geographic configuration. Use text-editors (notepad, notepad++) to check the actual separator in the csv files and to correct them if needed. 

#Description: This script integrates peaks resulting from discrete open-loop injections. 

#Inputs: 
#Rawfiles from Li-COR 7820 and Li-COR 7810
#corrected_map_injection files

#Outputs: 
#Integrated injection files (peak integration data)
#Integration plots (plots to check quality, of integrations)
#Baseline files (statistics for remarks containing 'baseline', optional, not required for further steps)

#Peak-max detection is based on difference between max and percentile-25 of each remark
#Integration window widths are fixed for every gas depending on the upstream-downstream IRGA configuration specified in corrected_map_injection files (12s for upstream, 23s for downstream instrument). 
#Baseline correction is performed for every peak individually as value of the first point in the integration window (4s before max of peak).

#If remarks that contain "baseline" are present, summary statistics are calculated and written to a different csv file (only as reference, they are not used for integration purposes). 

#REPEATED RUNS: 
#the script checks which data has already been integrated and skips it. If you need to re-integrate (after inspection of integration plots and corresponding correction of map_injection files), you must delete the integrated injections csv files from the 'Results_ppm' folder. 

#Clean Global environment
rm(list=ls())


# ---- Directories ----
#To test the repository functionality (with example data):
# project_root<- paste0(dirname(rstudioapi::getSourceEditorContext()$path),"/EXAMPLE_PROJECT")

#TO PROCESS YOUR OWN DATA, uncomment the following line and edit with the full path to your own your project folder (no closing "/"), eg:  

project_root<- "C:/Users/Camille Minaudo/OneDrive - Universitat de Barcelona/Documentos/PROJECTS/2026_DRYINGLAKE/data/DIC_smallVolumes_tests/IRGA"



#Data folders
folder_raw <- paste0(project_root,"/Rawdata") #contains unedited files downloaded from IRGA

#Map injections
folder_mapinjections<- paste0(project_root,"/Map_injections") #Contains corrected_map_injections csv files with start and stop times of remarks and their corresponding labels, corrections should be made manually when needed (editing the csvs and re-saving with "corrected_" prefix)

#Folder for plots
folder_plots<-  paste0(project_root,"/Integration_plots") #Here we will generate one pdf per gas and raw-file (auto-name), plots of each injection sequence (baseline correction & integration)
if (!dir.exists(folder_plots)) {
  # If it doesn't exist, create the folder
  dir.create(folder_plots)
}

#Folder for results
folder_results<- paste0(project_root,"/Results_ppm")#Here we will generate one csv per gas and raw-file (auto-name), with individual peak parameters.
if (!dir.exists(folder_results)) {
  # If it doesn't exist, create the folder
  dir.create(folder_results)
}




# ---- Packages & functions ----
#Installs (if needed) and loads required packages:
required_pkgs <- c("tidyverse",
                   "readxl",
                   "lubridate",
                   "pracma",
                   "stringr",
                   "ggpmisc")

for (pkg in required_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
  library(pkg, character.only = TRUE)
}

#Load repository functions
repo_root <- dirname(rstudioapi::getSourceEditorContext()$path)
files.sources = list.files(path = paste0(repo_root,"/functions"), full.names = T)
for (f in files.sources){source(f)}



###1. Check data to integrate####
#Get rawfiles
rawfiles<- list.files(path = folder_raw, pattern = ".TXT")

#Get corrected maps of injections
mapscorrect <- list.files(path = folder_mapinjections, pattern = "map_injections_")
print(mapscorrect)

rawtointegrate <- rawfiles
print(rawtointegrate)

###2. Integration loop####

integratePeaks_IRGA(path2IRGA_file = paste0(folder_raw,"/","26042013.TXT"), 
                    path2injection_map = paste0(folder_mapinjections,"/","map_injections_20260420.csv"))


integratePeaks_IRGA(path2IRGA_file = paste0(folder_raw,"/","26042013.TXT"), 
                    path2injection_map = paste0(folder_mapinjections,"/","map_injections_20260420.csv"))


# Raw to integrated peaks#

#Clean Global environment
rm(list=ls())


# ---- Directories ----
#To test the repository functionality (with example data):
# project_root<- paste0(dirname(rstudioapi::getSourceEditorContext()$path),"/EXAMPLE_PROJECT")

#TO PROCESS YOUR OWN DATA, uncomment the following line and edit with the full path to your own your project folder (no closing "/"), eg:  

project_root<- "C:/Users/Camille Minaudo/OneDrive - Universitat de Barcelona/Documentos/PROJECTS/2026_DRYINGLAKE/data/DIC_smallVolumes_tests/IRGA/Timeincubationtest/"



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
rawfiles<- list.files(path = folder_raw)



#Import all raw data contained in myfolder
raw_data<- read_IRGA(myfolder = folder_raw)
raw_data$unixtime_original <- raw_data$unixtime

raw_data <- raw_data %>% group_by(IRGAtime) %>% summarise(across(everything(), ~last(.))) %>% ungroup()

raw_data$timeonly <- format(raw_data$PosiXct.time, format = "%H:%M:%S")


binned <- raw_data %>%
  mutate(
    date = as.Date(date),
    time_seconds = as.numeric(hms::as_hms(timeonly)),
    time_bin = floor(time_seconds / 60) * 60  # bin to 1-minute intervals
  ) %>%
  distinct(date, time_bin)          # keep only unique date+bin combos

plt <- ggplot(binned, aes(x = time_bin, y = factor(date))) +
  geom_tile(aes(width = 60, height = 0.8), fill = "steelblue") +
  scale_x_continuous(
    name = "Time of day",
    breaks = seq(0, 86400, by = 3600),
    labels = function(s) format(hms::as_hms(s), "%H:%M")
  ) +
  labs(title = "Data coverage by time of day", y = "Date") +
  theme_bw(base_size = 13)


### 2. Read Maps of injections


#Get list of maps of injections
maps_available <- list.files(path = folder_mapinjections, pattern = ".csv")
print(maps_available)

# load them all and look at temporal match with IRGA data
mapinj <- NULL
for (f in maps_available){
  message("Reading ", f)
  mapinj <- rbind(mapinj,
                  read_injections_map(path2file = paste0(folder_mapinjections,"/",f)))
  
}

mapinj_prep <- mapinj %>%
  mutate(
    date = as.Date(date),
    x_mid = (as.numeric(hms::as_hms(time_start)) + 
               as.numeric(hms::as_hms(time_stop))) / 2
  )

# your existing plot +
plt + geom_point(data = mapinj_prep,
           aes(x = x_mid, y = factor(date)),
           color = "red", size = 3)



# extract peaks
for (f in maps_available){
  message("Extracting ", f)
  mapinj_sel <- mapinj[mapinj$file == f,]
  
  mytitle <- gsub(pattern = "Map_injections_", replacement = "", x = f)
  mytitle <- gsub(pattern = ".csv", replacement = "", x = mytitle)
  
  integratePeaks_IRGA(raw_data = raw_data, 
                      mapinj = mapinj_sel,
                      title = mytitle)
  warnings()
  
}







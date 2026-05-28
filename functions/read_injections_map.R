


detect_sep <- function(file) {
  first_line <- readLines(file, n = 1)
  
  seps <- c("," , ";" , "\t" , "|")
  
  counts <- sapply(seps, function(s)
    stringr::str_count(first_line, fixed(s))
  )
  
  seps[which.max(counts)]
}

parse_time <- function(t) {
  result <- strptime(t, "%H:%M:%S")           # try HH:MM:SS first
  fix <- is.na(result)
  result[fix] <- strptime(t[fix], "%H:%M")    # fall back to HH:MM
  format(result, "%H:%M:%S")
}


read_injections_map <- function(path2file){
  
  sep <- detect_sep(path2file)
  
  #Import corrected map of injections
  mapinj<- read.csv(path2file, sep = sep) %>% 
    filter(!is.na(label)) %>%
    filter(label!="") %>%
    select(-date)
  
  
  # check if there are duplicates in labels
  n_duplicates <- sum(duplicated(mapinj$label))
  if(n_duplicates > 0){
    for (k in which(duplicated(mapinj$label))){
      
      message(paste0("... Duplicated label name for row with label = ",mapinj$label[k]," ---> Changing automatically"))
      
      ind = which(mapinj$label == mapinj$label[k])
      ii = 0
      for (l in ind){
        ii = ii + 1
        mapinj$label[l] <-  paste0(mapinj$label[l],"_",ii)
      }
      
    }
  }
  
  mapinj$label <- gsub("_", "-", mapinj$label)
  
  mapinj$label <- paste0(mapinj$label, "_1")
  
  #Get date of analysis 
  dayofanalysis <- read.csv(path2file, sep = sep) %>% 
    select(date) %>% pull() %>% unique()
  
  dayofanalysis <- dayofanalysis[1]
  
  mapinj$date <- as.Date(dayofanalysis, "%d/%m/%Y")
  
  # Making sure format for time_start and time_stop is correct
  mapinj <- mapinj %>%
    mutate(
      time_start = parse_time(time_start),
      time_stop  = parse_time(time_stop)
    )
  
  # Keeping only the columns that we agreed on
  mapinj <- mapinj %>%
    select(date, label, time_start, time_stop, n_injections)
  
  mapinj$file <- basename(path2file)
  
  return(mapinj)
}






read_IRGA <- function(datafile){
  data <- read.delim(datafile, header = F, sep = ",")
  
  # get rid of all raws where first columns doesn't start with a M
  ind_keep = grep(x=data$V1, pattern = "M")
  data <- data[ind_keep, ]
  
  
  names(data)[c(1:8)] <- c("dataformat","DATE","TIME","plotnum","timestamp","CO2","Patm","flowrate")
  
  data$unixtime = as.numeric(as.POSIXct(paste(data$DATE,data$TIME, sep = " "), tz = "CET", format = "%d/%m/%y %H:%M:%S"))
  
  
  my_data <- data.frame(date = as.Date(data$DATE, format = "%d/%m/%y"),
                        IRGAtime = data$TIME,
                        unixtime = data$unixtime,
                        PosiXct.time = as.POSIXct(data$unixtime, tz = "CET"),
                        flowrate = as.numeric(data$flowrate),
                        CO2 = as.numeric(data$CO2), #ppb
                        Press = as.numeric(data$Patm))
  
  return(my_data)
}

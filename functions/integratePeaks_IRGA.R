


integratePeaks_IRGA <- function(path2IRGA_file, 
                                path2injection_map, 
                                secs_diff_REAL_minus_IRGA = 0, # before being synced on 20/04/2026, there was an apparent difference of secs_diff_REAL_minus_IRGA = 274309 seconds
                                title = "dummytitle"){
  
  message(paste("Integrating peaks from",basename(path2IRGA_file)))
  
  #Import data from rawfile
  raw_data<- read_IRGA(datafile = path2IRGA_file)
  raw_data$unixtime_original <- raw_data$unixtime
  
  raw_data <- raw_data %>% group_by(IRGAtime) %>% summarise(across(everything(), ~last(.))) %>% ungroup()
  
  #Import corrected map of injections
  mapinj<- read.csv(path2injection_map) %>% 
    filter(!is.na(label)) %>%
    filter(label!="") %>%
    select(-date)
  
  # mapinj$label <- paste0(mapinj$label, "_1")
  
  #Get date of analysis 
  dayofanalysis <- read.csv(path2injection_map) %>% 
    select(date) %>% pull() %>% unique()
  
  dayofanalysis <- dayofanalysis[1]
  
  mapinj$date <- as.Date(dayofanalysis, "%d/%m/%Y")
  
  # correcting IRGA time based on secs_diff_REAL_minus_IRGA
  raw_data$unixtime <- raw_data$unixtime_original + secs_diff_REAL_minus_IRGA   
  
  
  gas <- "CO2"
  
  #Create tables where baseline and injections will be saved
  
  #Initialize data frame for injections
  A<- data.frame(
    dayofanalysis=character(),
    label = character(),
    peak_id = character(),
    peaksum = double(),
    secondspeak =double(),
    peak_base= double(),
    peakmax = double(),
    unixtime_ofmax = double(),
    raw_peaksum = double(),
    peakSNR = double(),
    avg_remark=double(),
    sd_remark=double(),
    n_remark=double(),
    avg_baseline=double(),
    sd_nopeak=double(),
    n_nopeak=double())
  
  
  #Initialize list of plots to save integration plots
  plotspeak <- list()
  
  #loop over different labels of rawfile i
  for (inj in mapinj$label){

    #Unixstart, time_start from mapinj in unix time format
    unixstart<- as.numeric(as.POSIXct(paste(mapinj[mapinj$label==inj,]$date,
                                            mapinj[mapinj$label==inj,]$time_start), tz = "CET"))

    #Unixend, time_stop from mapinj in unix time format
    unixend<- as.numeric(as.POSIXct(paste(mapinj[mapinj$label==inj,]$date,
                                          mapinj[mapinj$label==inj,]$time_stop), tz = "CET"))

    if (unixend < unixstart){
      message("... wrong start or stop time because stop_time > start_time")
    }
    if (unixend - unixstart < 60 & unixend - unixstart>0){
      message("... time window is shorter than 1 min, check if this is correct")
    }
    if (unixend - unixstart > 10*60){
      message("... time window is longer than 10 min, check if this is correct")
    }
    
    # ggplot(raw_data, aes(unixtime, CO2))+geom_path()+
    #   geom_vline(xintercept = c(unixstart, unixend))+
    #   theme_bw()
    
    #Subset data from injection sequence inj 
    inj_data<- raw_data[between(raw_data$unixtime, unixstart, unixend),]  
    
    # ggplot(inj_data, aes(unixtime, CO2))+geom_path()+
    #   theme_bw()
    
    #Make sure whole inj_data has the correct label inj
    inj_data$label<- inj
    ###2.2. Injections#####
    print(paste0(gas," Injection sample: ", inj))
    
    #Detect and integrate peaks, plot results, calculate  baseline SD within label for Signal to Noise ratio
    
    ##_Detect peaks#####
    
    #Find local maxima in remark and add max_id (label_1,label_2,...) : 
    #Criteria for local maximum:
    # at least 1 increase before and 2 decrease after to be considered as local maxima
    # minimum peak height to be detected is > 1/5 of maximum difference between max point and percentil 25% in all remark
    # at leas 12 points between localmaxima
    
    low_boundary_peak<- inj_data %>% summarise(low=quantile(!!sym(gas),0.25)) %>% pull(low) %>% as.numeric()
    high_boundary_peak<- inj_data %>% summarise(high=max(!!sym(gas),na.rm=T)) %>% pull(high)
    
    
    inj_data <- inj_data %>%
      mutate(is_localmaxgas = ifelse(row_number() %in% findpeaks(!!sym(gas), 
                                                                 minpeakheight = ((high_boundary_peak-low_boundary_peak)/5)+low_boundary_peak, 
                                                                 nups=1, ndowns=2,
                                                                 minpeakdistance = 5)[, 2], TRUE, FALSE)) %>%
      mutate(peak_id = ifelse(is_localmaxgas, paste0(label,"_",cumsum(is_localmaxgas)), NA)) %>%  #Add unique peak_id for each local maximum found 
      ungroup()
    
    ##_Set window#####
    #Consider peakwindow as max height + 4 leading and X trailing points. (i.e. peak width == 12points), 
    
    inj_data <- inj_data %>%
      mutate(peak_id = map_chr(row_number(), function(idx) {
        #For each row, search for a non-na peak_id, look up to 4 seconds before and X seconds after the row i. Then assing the value of peak_id to the row i.
        #This results in the spread of the value of "peak_id" of the local maximum to secondsbefore_max seconds before and to secondsafter_max seconds after each identified maximum. 
        secondsbefore_max<- 4
        
        secondsafter_max<- 7
        
        # Check for peak_id in the window:
        surrounding_codes <- peak_id[seq(max(1, idx - secondsafter_max), min(n(), idx + secondsbefore_max))]  
        
        # Return the peak_id if it's available, otherwise return NA
        if (any(!is.na(surrounding_codes))) {
          return(first(na.omit(surrounding_codes)))  # Use the first valid peak_id found
        } else {
          return(NA)
        }
      }))
    
    
    ##_Integration#####
    
    #Get baseline avg and SD from outside the peak windows
    avg_nopeak<-inj_data %>% 
      filter(is.na(peak_id)) %>%
      summarise(avg=mean(!!sym(gas), na.rm=T)) %>% pull(avg)
    
    sd_nopeak<-inj_data %>% 
      filter(is.na(peak_id)) %>%
      summarise(nopeak_sd=sd(!!sym(gas), na.rm=T)) %>% pull(nopeak_sd)
    
    n_nopeak<-inj_data %>% 
      filter(is.na(peak_id)) %>%
      summarise(nopeak_n=sum(!is.na(!!sym(gas))))%>% pull(nopeak_n)
    
    #Get average value for whole remark
    avg_remark<- inj_data %>% 
      summarise(avg=mean(!!sym(gas), na.rm=T)) %>% pull(avg)
    sd_remark<- inj_data %>% 
      summarise(desv=sd(!!sym(gas), na.rm=T)) %>% pull(desv)
    n_remark<-inj_data %>% 
      summarise(remark_n=sum(!is.na(!!sym(gas)))) %>% pull(remark_n)
    
    #Summarise each peak_id (peaksum, peakmax, unixtimeofmax, raw_peaksum, peakSNR) add avg_remark, sd_remark
    integrated<- inj_data %>% 
      filter(!is.na(peak_id)) %>% #keep only data of peaks
      group_by(label, peak_id) %>% #For each peak_id do the following
      mutate(gas_bc=!!sym(gas) - first(!!sym(gas)),#Base-correct timeseries for duration of peak (using the concentration of the first point of integration window, before the peak )
             peak_base=first(!!sym(gas))) %>% 
      summarise(peaksum=sum(gas_bc),
                peak_base=mean(peak_base,na.rm=T),
                secondspeak=sum(!is.na(gas_bc)),
                peakmax=max(gas_bc,na.rm = T), 
                unixtime_ofmax=unixtime[gas_bc==peakmax],
                raw_peaksum=sum(!!sym(gas)),.groups = "keep") %>%
      mutate(dayofanalysis=dayofanalysis,
             peakSNR=peaksum/(sd_nopeak),
             avg_remark=avg_remark,
             sd_remark=sd_remark,
             n_remark=n_remark,
             avg_nopeak=avg_nopeak,
             sd_nopeak=sd_nopeak,
             n_nopeak=n_nopeak) %>% 
      ungroup()
    
    
    avg_peaksum<- mean(integrated$peaksum)
    sd_peaksum<- sd(integrated$peaksum)
    
    
    peakdataseries<- inj_data %>% 
      filter(!is.na(peak_id)) %>% #keep only data of peaks
      group_by(label, peak_id) %>% #For each peak_id do the following
      mutate(gas_bc=!!sym(gas) - ( (first(!!sym(gas)) + last(!!sym(gas)))/2 ))
    
    
    ###_Plots#####
    p<-ggplot()+
      geom_point(data=subset(peakdataseries,!is.na(peak_id)), aes(x=as.POSIXct(unixtime),y=gas_bc,col="2_peaks base corrected"))+
      geom_line(data=subset(peakdataseries), aes(x=as.POSIXct(unixtime),y=gas_bc,col="2_peaks base corrected"))+
      geom_point(data = integrated, aes(x=as.POSIXct(unixtime_ofmax,tz = "utc"), y=peaksum, col="3_peak integration"))+
      # geom_line(data = inj_data, aes(x=as.POSIXct(unixtime,tz = "utc"), y=gas_bc, col="1_base-corrected"))+
      geom_line(data = inj_data, aes(x=as.POSIXct(unixtime,tz = "utc"), y=!!sym(gas), col="1_raw data"), linetype = 2)+
      scale_y_continuous(name=paste("signal", gas))+
      scale_x_datetime(name="IRGA time (UTC)",timezone = "utc")+
      labs(col="")+
      ggtitle(paste0(dayofanalysis,", injection: ",inj))+
      theme_bw()+
      annotate("text",x = as.POSIXct(min(integrated$unixtime_ofmax)-50), 
               y = min(integrated$peaksum)*0.8, 
               label = paste ("Avg: ", round(avg_peaksum, 2), " ± ", round(sd_peaksum, 2), " (CV= ",round(sd_peaksum/avg_peaksum,2),")" ), color = "black", hjust = 0, 
               vjust = 1, 
               size = 4, 
               fontface = "italic")
    
    
    
    # Store each plot in the list
    plotspeak[[inj]] <- p
    
    #Add integrations of inj to injections table
    A <-rbind(A,integrated)
  } 
  #Save areas of injections for rawfile i   
  write.csv(A,
            file = paste0(folder_results,"/", "integrated_injections_",gas, "_", title, ".csv"),
            row.names = F)
  
  #Save plots of integrations: use i for naming convention of pdf
  print(paste0("Plotting ",gas," integrations rawfile: ", basename(path2IRGA_file)))
  #plot every injection sequence and their integrals: 
  setwd(folder_plots)
  pdf(file = paste0("Integrations_",gas, "_",title,".pdf"))  # Open PDF device
  
  # Loop through the list of plots and print each plot
  for (plot_name in names(plotspeak)) {
    print(plotspeak[[plot_name]])
  }
  
  dev.off()  # Close the PDF device
}

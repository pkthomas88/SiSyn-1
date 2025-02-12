#install.packages("googledrive")
#install.packages("tidyverse")
require(tidyverse)
require(googledrive)
require(stringr)
require(lubridate)
require(reshape)
require(gtools)
require(dplyr)

#get folder URL from google drive with discharge data
folder_url<-"https://drive.google.com/drive/folders/19lemMC09T1kajzryEx5RUoOs3KDSbeAX"

#get ID of folder
folder<-drive_get(as_id(folder_url))

#get list of csv files from folder
csv_files<-drive_ls(folder, type="csv")

csv_files<-csv_files[-c(26),]

#split ".csv" from document names
csv_files$files<-word(csv_files$name, 1, sep = "\\.csv")

setwd("/Users/keirajohnson/Box Sync/Keira_Johnson/SiSyn")

#read in discharge log
QLog<-read.csv("DischargeLog.csv")
names(QLog)[3]<-"files"

#merge discharge log and list of csv files in google drive
RefTable<-merge(QLog, csv_files, by="files")

#extract columns of the google drive files and site name
RefTable<-RefTable[,c(1,3,8)]

RefTable<-RefTable[-c(132),]

#read in master chemistry data
master<-read.csv("master.csv")

#rename column
names(master)[2]<-"Stream"

#subset Si data
masterSi<-subset(master, master$variable=="DSi")

#rename columns
names(masterSi)[4]<-"Date"
names(masterSi)[6]<-"Si"

#convert date to date format
masterSi$Date<-as.Date(masterSi$Date, "%m/%d/%y")

#make list of unique sites from reference table
StreamList<-unique(RefTable$Stream)
QList<-unique(RefTable$files)

#create function to turn date into day of water year
hydro.day.new = function(x, start.month = 10L){
  start.yr = year(x) - (month(x) < start.month)
  start.date = make_date(start.yr, start.month, 1L)
  as.integer(x - start.date + 1L)
}

#create lists of Q and Date names used in different files
DischargeList<-c("MEAN_Q", "Discharge", "InstantQ")
DateList<-c("Date", "dateTime")

#start loop - will replicate code inside for each unique site
for (i in 1:length(StreamList)) {

#extract name from site list
stream<-StreamList[i]

#extract row of reference table corresponding to site (extract stream site)
ref<-subset(RefTable, RefTable$Stream==stream)

#extract row of csv list table corresponding discharge file (extract discharge site)
csv<-subset(csv_files, csv_files$files==ref$files)

#read in proper discharge file
Q<-read.csv(drive_download(file = as_id(csv$id), overwrite = TRUE)$name)

#name discharge column "Q"
names(Q)[which(colnames(Q) %in% DischargeList)]<-"Q"

#name date column "Date"
names(Q)[which(colnames(Q) %in% DateList)]<-"Date"

#set dates to date format
Q$Date<-as.Date(Q$Date)

Q<-aggregate(Q, by=list(Q$Date), mean)

#remove rows with NA in discharge column
Q<-Q[!(is.na(Q$Q)),]

#paste units from reference file to units column in current datafile
Q$Units<-ref$Units[1]

#convert all Q file units to CMS
Q$Qcms<-ifelse(Q$Units=="cms", Q$Q, 
                 ifelse(Q$Units=="cfs", Q$Q*0.0283,
                        ifelse(Q$Units=="Ls", Q$Q*0.001,
                               ifelse(Q$Units=="cmd", Q$Q*1.15741e-5, ""))))

#subset master silica file to individual site
Si<-subset(masterSi, masterSi$Stream==StreamList[i])

#find minimum date of Si file
Simin<-min(Si$Date)
#convert to day of water year
MinDay<-as.numeric(hydro.day.new(Simin))

#find maximum date of Si file
Simax<-max(Si$Date)
#convert to day of water year
MaxDay<-as.numeric(hydro.day.new(Simax))

#find difference between beginning of next water year and end of Si file
si_water_year_diff<-365-MaxDay

#subset Q file associated with Si file starting at beginning of water year of start of Si file and ending at end
#of water year of last Si file date
Qshort<-Q[Q$Date > (Simin - MinDay) & Q$Date < (Simax + si_water_year_diff),]

#extract date and discharge columns
Qshort<-Qshort %>%
  dplyr::select(Date, Q)

#write to new folder
setwd("/Users/keirajohnson/Box Sync/Keira_Johnson/SiSyn/WRTDS_prep/")

#write csv of discharge file
write.csv(Qshort, paste0(StreamList[i], "_Q_WRTDS.csv"), row.names = FALSE)

#find minimum date of Si file
Qmin<-min(Qshort$Date)
#convert to day of water year
QMinDay<-as.numeric(hydro.day.new(Qmin))

#find maximum date of Si file
Qmax<-max(Qshort$Date)
#convert to day of water year
QMaxDay<-as.numeric(hydro.day.new(Qmax))

#find difference between beginning of next water year and end of Si file
Q_water_year_diff<-365-QMaxDay

#subset Q file associated with Si file starting at beginning of water year of start of Si file and ending at end
#of water year of last Si file date
SiShort<-Si[Si$Date > (Qmin) & Si$Date < (Qmax),]

#extract date and Si columns of Si file
Sidata<-SiShort %>%
  dplyr::select(Date, Si)

#create remarks variable
remarks<-""

#add remarks column between date and Si columns - required for WRTDS
Sidata<-add_column(Sidata, remarks, .after = "Date")

#write Si file for WRTDS
write.csv(Sidata, paste0(StreamList[i], "_Si_WRTDS.csv"), row.names = FALSE)

}

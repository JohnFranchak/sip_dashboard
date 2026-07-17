library(tidyverse)
library(hms)
library(rstatix)
library(pins)
library(REDCapR)
library("googledrive")
drive_auth(email = TRUE)

board <- board_folder("/Volumes/padlab/study_sensorsinperson/data_processed/datasets/", versioned = T)
board_gd <- board_gdrive(path = as_id("1OZlphhu6vYm1A2Bm2-zD7a4luS5nGWgS"))

#IDS FOR REDCAP AND IMU
study_dir <- "/Volumes/padlab/study_sensorsinperson/data_processed/imu/"
id_session <- list.files(study_dir, pattern = "\\d+_\\d+$", include.dirs = T)
id_session_keep <- id_session[file.exists(str_glue("{study_dir}{id_session}/infant_position_predictions_4s.csv"))]
ids <- map_chr(id_session_keep, ~ strsplit(.x, "_")[[1]][[1]])
sessions <- map_chr(id_session_keep, ~ strsplit(.x, "_")[[1]][[2]])


#REDCAP DATA
uri <- "https://redcap.ucr.edu/api/"
source("api_token.R")

id_session_strings  <-  paste0(ids, "_", as.character(factor(sessions, levels = 1:4, labels = c("visit_1_arm_1", "visit_2_arm_1", "visit_3_arm_1", "visit_4_arm_1"))))

redcap <- redcap_read(redcap_uri = uri, token = api_token, forms = c("session_notes"), guess_type = F) %>% 
  .[["data"]] %>% select(study_id, redcap_event_name, time_gopro_start:cg_off_6_reason) %>% 
  mutate(id_redcap_session = paste0(study_id, "_", redcap_event_name)) %>% 
  filter(id_redcap_session %in% id_session_strings) %>% 
  mutate(session_num = as.numeric(str_extract(redcap_event_name, "\\d+")))

# For Redcap Participant Level Board
redcap_id <- redcap_read(redcap_uri = uri, token = api_token, fields = c("study_id","dob","sex"), guess_type = F, raw_or_label = "label") %>% 
  .[["data"]] %>% filter(study_id %in% unique(ids), redcap_event_name %in% c("Intro Call")) %>% select(-redcap_event_name)

redcap_visits <- redcap_read(redcap_uri = uri, token = api_token, fields = c("study_id","visit_date","zoom_call_date"), guess_type = F, raw_or_label = "label") %>% 
  .[["data"]] %>% filter(study_id %in% unique(ids), redcap_event_name %in% c("Intro Call", "Schedule 2", "Schedule 3", "Visit 4")) %>% 
  mutate(visit_date = ifelse(is.na(visit_date), zoom_call_date, visit_date),
         session = as.character(factor(redcap_event_name, levels = c("Intro Call", "Schedule 2", "Schedule 3", "Visit 4"), labels = 1:4))) %>% 
  select(-redcap_event_name, -zoom_call_date)

redcap_demo <- redcap_read(redcap_uri = uri, token = api_token, forms = c("demographics"), guess_type = F, raw_or_label = "label") %>% 
  .[["data"]] %>% filter(study_id %in% unique(ids), redcap_event_name %in% c("Visit 1")) %>% select(-redcap_event_name)

redcap_session <- redcap_read(redcap_uri = uri, token = api_token, forms = c("motor_milestones","mulborne_cg", "parent_stress", "aims","aims_reliability"), guess_type = F, raw_or_label = "label") %>% 
  .[["data"]] %>% filter(study_id %in% unique(ids), redcap_event_name %in% c("Visit 1", "Visit 2", "Visit 3", "Visit 4")) %>% 
  mutate(session = str_extract(redcap_event_name, "\\d")) %>% select(-redcap_event_name)

session_export <- left_join(redcap_session, redcap_id) %>% left_join(redcap_demo)
session_export <- session_export %>% left_join(redcap_visits)
session_export <- session_export %>% rename(id = study_id) %>% relocate(session, .after = "id") %>% relocate(dob, .after = "session") %>% 
  relocate(sex, .after = "dob") %>% relocate(visit_date, .after = "dob")

board %>% pin_write(name = "redcap_data", x = session_export,
                    title = "Participant and session data from redcap",
                    description = "Demographics, parent surveys, and AIMS",
                    type = "csv")
board_gd %>% pin_write(name = "redcap_data", x = session_export,
                       title = "Participant and session data from redcap",
                       description = "Demographics, parent surveys, and AIMS",
                       type = "csv")

#IMU DATA 

read_session <- function(id, session) {
  predictions <- read_csv(str_glue("{study_dir}{id}_{session}/infant_position_predictions_4s.csv")) %>% 
    rename(time = time_start) %>% mutate(time_rounded = as.numeric(time)) %>% 
    select(-exclude_period, -nap_period)

  cg_exists <- FALSE
  if (file.exists(str_glue("{study_dir}{id}_{session}/cg_position_predictions_4s.csv"))) {
      cg_predictions <- read_csv(str_glue("{study_dir}{id}_{session}/cg_position_predictions_4s.csv")) %>% 
        rename(cgpos = pos) %>% mutate(time_rounded = as.numeric(time_start)) %>% select(-cg_exclude_period)
      cg_exists <- TRUE
  }
  
  exclude_times <- redcap %>% filter(study_id == id, session_num == session)
  sync_point <- exclude_times$sync_point_la
  
  inf_exclude = exclude_times %>% select(matches("^time_off_\\d_(start|end)")) %>% 
    pivot_longer(cols = everything(), names_to = c("event", ".value"), names_pattern = "time_off_(\\d)_(.*)") %>% 
    drop_na() %>% separate(start, into = c("start_hour", "start_minute")) %>% 
    separate(end, into = c("end_hour", "end_minute")) %>%
    mutate(across(start_hour:end_minute, as.numeric),
      start_time = make_datetime(year = year(sync_point), month = month(sync_point), day = day(sync_point), hour = start_hour, min = start_minute, sec = 0, tz = tz(sync_point)),
      end_time = make_datetime(year = year(sync_point), month = month(sync_point), day = day(sync_point), hour = end_hour, min = end_minute, sec = 0, tz = tz(sync_point))) %>% 
    select(start_time, end_time)
    
  
  nap_exclude = exclude_times %>% select(matches("^time_nap_\\d_(start|end)")) %>% 
    pivot_longer(cols = everything(), names_to = c("event", ".value"), names_pattern = "time_nap_(\\d)_(.*)") %>% 
    drop_na() %>% separate(start, into = c("start_hour", "start_minute")) %>% 
    separate(end, into = c("end_hour", "end_minute")) %>%
    mutate(across(start_hour:end_minute, as.numeric),
           start_time = make_datetime(year = year(sync_point), month = month(sync_point), day = day(sync_point), hour = start_hour, min = start_minute, sec = 0, tz = tz(sync_point)),
           end_time = make_datetime(year = year(sync_point), month = month(sync_point), day = day(sync_point), hour = end_hour, min = end_minute, sec = 0, tz = tz(sync_point)))  %>% 
    select(start_time, end_time)
  
  predictions <- predictions %>% left_join(inf_exclude, by = join_by(between(time, start_time, end_time))) %>% 
    mutate(exclude_period = as.numeric(!is.na(start_time))) %>% select(-start_time, -end_time)
  predictions <- predictions %>% left_join(nap_exclude, by = join_by(between(time, start_time, end_time))) %>% 
    mutate(nap_period = as.numeric(!is.na(start_time))) %>% select(-start_time, -end_time)
  
  if (cg_exists) {
    cg_exclude = exclude_times %>% select(matches("^cg_off_\\d_(start|end)")) %>% 
      pivot_longer(cols = everything(), names_to = c("event", ".value"), names_pattern = "cg_off_(\\d)_(.*)") %>% 
      drop_na()  %>% separate(start, into = c("start_hour", "start_minute")) %>% 
      separate(end, into = c("end_hour", "end_minute")) %>%
      mutate(across(start_hour:end_minute, as.numeric),
             start_time = make_datetime(year = year(sync_point), month = month(sync_point), day = day(sync_point), hour = start_hour, min = start_minute, sec = 0, tz = tz(sync_point)),
             end_time = make_datetime(year = year(sync_point), month = month(sync_point), day = day(sync_point), hour = end_hour, min = end_minute, sec = 0, tz = tz(sync_point)))  %>% 
      select(start_time, end_time)
    
    cg_predictions <- cg_predictions %>% left_join(cg_exclude, by = join_by(between(time_start, start_time, end_time))) %>% 
      mutate(cg_exclude_period = as.numeric(!is.na(start_time))) %>% select(-start_time, -end_time, -time_start)
    
    sync <- left_join(predictions, cg_predictions, by = join_by(closest(time_rounded >= time_rounded))) # %>% drop_na(cgpos) 
  } else {
    sync <- predictions
  }
  
  sync$id = id
  sync$session = session
  sync$time_plot <- as_hms(force_tz(sync$time, "America/Los_Angeles"))
  return(sync)
}
ds <- map2_dfr(ids, sessions, read_session) 

ds <- ds %>% 
  mutate(pos = ifelse(pos == "Upright", "Standing", pos),
          cgpos = ifelse(cgpos == "Upright", "Standing", cgpos),
          pos = factor(pos, levels=c("Supine", "Prone", "Sitting", "Standing", "Held")),
          cgpos = factor(cgpos, levels=c("Down", "Standing")),
          restraint = factor(restraint, levels=c("Restrained","Unrestrained"))) %>%
 select(-time_rounded.x, -time_rounded.y) 

board %>% pin_write(name = "imu_raw_samples", x = ds,
                    title = "Infant and Caregiver Raw Position",
                    description = "Raw position predictions sampled every 1 second. 
                    Data are NOT filtered and include unusable samples.",
                    metadata = list(infant_model = "TDCP-March2025", cg_model = "Nov2025", rest_model = "May2026"),
                    type = "parquet")
board_gd %>% pin_write(name = "imu_raw_samples", x = ds,
                       title = "Infant and Caregiver Raw Position",
                       description = "Raw position predictions sampled every 1 second. 
                    Data are NOT filtered and include unusable samples.",
                       metadata = list(infant_model = "TDCP-March2025", cg_model = "Nov2025", rest_model = "May2026"),
                       type = "parquet")

# Sleep and TCDS

study_dir <- "/Volumes/padlab/study_sensorsinperson/data_processed/lena_sleep_tcds/"
files <- list.files(study_dir, pattern = ".csv", include.dirs = F, full.names = T)

sleep_tcds <- read_csv(files)
sleep_tcds <- sleep_tcds %>% 
  mutate(time_start = mdy_hms(str_remove(StartTime, " (America/Los_Angeles)")),
         time_end = mdy_hms(str_remove(EndTime, " (America/Los_Angeles)"))) %>% 
  select(-(RecordingDate:EndTime), -(ProgramType:RecorderTransferDateTime)) %>%
  relocate(time_start:time_end, .before = Duration_Secs) %>% 
  relocate(sleep_prob:cds_pred, .before = Duration_Secs) 

board %>% pin_write(name = "sleep_tcds", x = sleep_tcds,
                    title = "Infant and Caregiver Raw Position",
                    description = "LENA predictions using Bang, Kachergis, Weisleder, and Marchman (2022) Shiny Algorithm. Does not include parent logged exclude periods",
                    metadata = list(model_url = "https://kachergis.shinyapps.io/classify_cds_ods/"),
                    type = "parquet")
board_gd %>% pin_write(name = "sleep_tcds", x = sleep_tcds,
                    title = "Infant and Caregiver Raw Position",
                    description = "LENA predictions using Bang, Kachergis, Weisleder, and Marchman (2022) Shiny Algorithm. Does not include parent logged exclude periods",
                    metadata = list(model_url = "https://kachergis.shinyapps.io/classify_cds_ods/"),
                    type = "parquet")
  

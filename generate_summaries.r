library(tidyverse)
library(hms)
library(rstatix)
library(pins)
library("googledrive")
drive_auth(email = TRUE)

board <- board_folder("/Volumes/padlab/study_sensorsinperson/data_processed/datasets/", versioned = T)
board_gd <- board_gdrive(path = as_id("1OZlphhu6vYm1A2Bm2-zD7a4luS5nGWgS"))

# IMU Data
study_dir <- "/Volumes/padlab/study_sensorsinperson/data_processed/imu/"
id_session <- list.files(study_dir, pattern = "\\d+_\\d+$", include.dirs = T)
id_session_keep <- id_session[file.exists(str_glue("{study_dir}{id_session}/infant_position_predictions_4s.csv"))]
ids <- map_chr(id_session_keep, ~ strsplit(.x, "_")[[1]][[1]])
sessions <- map_chr(id_session_keep, ~ strsplit(.x, "_")[[1]][[2]])

read_session <- function(id, session) {
  predictions <- read_csv(str_glue("{study_dir}{id}_{session}/infant_position_predictions_4s.csv")) %>% 
    rename(time = time_start) %>% mutate(time_rounded = round(as.numeric(time)))
  
  cg_predictions <- read_csv(str_glue("{study_dir}{id}_{session}/cg_position_predictions_4s.csv")) %>% 
    rename(cgpos = pos) %>% mutate(time_rounded = round(as.numeric(time_start))) %>% 
    select(-time_start)
  
  # windows <- read_csv(str_glue("{study_dir}{id}_{session}/windows_4s.csv"))  %>% 
  #   rename(time = temp_time) %>% 
  #   select(-(time_sec:time_sec3))
  sync <- left_join(predictions, cg_predictions) # %>% left_join(windows)
  sync$id = id
  sync$session = session
  sync$time_plot <- as_hms(force_tz(sync$time, "America/Los_Angeles"))
  return(sync)
  #sync_filt <- sync %>% filter(nap_period == 0, exclude_period == 0)
}
ds <- map2_dfr(ids, sessions, read_session)

ds <- ds %>% mutate(pos = ifelse(pos == "Upright", "Standing", pos),
                    pos = factor(pos, levels=c("Supine", "Prone", "Sitting", "Standing", "Held")),
                    restraint = factor(restraint, levels=c("Restrained","Unrestrained")))

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
                    description = "LENA predictions using Bang, Kachergis, Weisleder, and Marchman(2022) Shiny Algorithm",
                    metadata = list(model_url = "https://kachergis.shinyapps.io/classify_cds_ods/"),
                    type = "parquet")
board_gd %>% pin_write(name = "sleep_tcds", x = sleep_tcds,
                    title = "Infant and Caregiver Raw Position",
                    description = "LENA predictions using Bang, Kachergis, Weisleder, and Marchman(2022) Shiny Algorithm",
                    metadata = list(model_url = "https://kachergis.shinyapps.io/classify_cds_ods/"),
                    type = "parquet")
  

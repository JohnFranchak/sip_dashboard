library(tidyverse)
library(hms)
library(rstatix)
library(pins)

board <- board_folder("/Volumes/padlab/study_sensorsinperson/data_processed/datasets/", versioned = T)
board_gh <- board_folder("datasets/", versioned = T)

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
  
  windows <- read_csv(str_glue("{study_dir}{id}_{session}/windows_4s.csv"))  %>% 
    rename(time = temp_time) %>% 
    select(-(time_sec:time_sec3))
  sync <- left_join(predictions, cg_predictions) %>% left_join(windows)
  sync$id = id
  sync$session = session
  sync$time_plot <- as_hms(force_tz(sync$time, "America/Los_Angeles"))
  
  sync_filt <- sync %>% filter(nap_period == 0, exclude_period == 0)
}
ds <- map2_dfr(ids, sessions, read_session)

ds <- ds %>% mutate(pos = ifelse(pos == "Upright", "Standing", pos),
                    pos = factor(pos, levels=c("Supine", "Prone", "Sitting", "Standing", "Held")))

#write_csv(ds, "/Volumes/padlab/study_sensorsinperson/data_processed/datasets/infant_raw_position.csv")

board %>% pin_write(name = "imu_raw_samples", x = ds,
                    title = "Infant and Caregiver Raw Position",
                    description = "Raw position predictions sampled every 1 second. 
                    Data are filtered to only include usable samples.",
                    metadata = list(infant_model = "TDCP-March2025", cg_model = "Nov2025"),
                    type = "parquet")
board_gh %>% pin_write(name = "imu_raw_samples", x = ds,
                       title = "Infant and Caregiver Raw Position",
                       description = "Raw position predictions sampled every 1 second. 
                    Data are filtered to only include usable samples.",
                       metadata = list(infant_model = "TDCP-March2025", cg_model = "Nov2025"),
                       type = "parquet")
write_board_manifest(board_gh)

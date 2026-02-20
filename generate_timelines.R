library(tidyverse)
library(scales)
library(REDCapR)
library(hms)
library(patchwork)
library(tidyquant)

theme_update(text = element_text(size = 12),
             axis.text.x = element_text(size = 12, color = "black"), 
             axis.title.x = element_text(size = 14),
             axis.text.y = element_text(size = 12,  color = "black"), 
             axis.title.y = element_text(size = 14), 
             panel.background = element_blank(),panel.border = element_blank(), 
             panel.grid.major = element_blank(),
             panel.grid.minor = element_blank(), axis.line = element_blank(), 
             axis.ticks.length=unit(.25, "cm"), 
             legend.key = element_rect(fill = "white")) 
pal <-  c("#F0E442","#009E73","#56B4E9", "#E69F00","#0072B2") %>%  set_names(c("Standing", "Sitting", "Prone", "Supine", "Held"))

uri <- "https://redcap.ucr.edu/api/"
source("api_token.R")
all_events <- redcap_event_instruments(redcap_uri = uri, token = api_token)$data

# Find which participants are processed
study_dir <- "/Volumes/padlab/study_sensorsinperson/data_processed/imu/"
id_session <- list.files(study_dir, pattern = "\\d+_\\d+$", include.dirs = T)
id_session_keep <- id_session[file.exists(str_glue("{study_dir}{id_session}/infant_position_predictions_4s.csv"))]
ids <- map_chr(id_session_keep, ~ strsplit(.x, "_")[[1]][[1]])
sessions <- map_chr(id_session_keep, ~ strsplit(.x, "_")[[1]][[2]])

make_timeline <- function(id, session) {
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
  sync$time_plot <- as_hms(force_tz(sync$time, "America/Los_Angeles"))
  
  sync_filt <- sync %>% filter(nap_period == 0, exclude_period == 0)
  
  session_string  <-  as.character(factor(session, levels = 1:4, labels = c("visit_1_arm_1", "visit_2_arm_1", "visit_3_arm_1", "visit_4_arm_1")))
  
  
  events <- all_events %>% filter(str_detect(unique_event_name, str_glue("visit_{session}")),
                                  form == "hour_activity") %>%
    filter(str_detect(unique_event_name, "test", negate = T)) %>% pull(unique_event_name)
  ema <- redcap_read(redcap_uri = uri, token = api_token, events = events, records = id, forms = "hour_activity")$data %>% 
    filter(str_detect(redcap_event_name, "test", negate = T))
  
  
  ema_plot <- tibble(redcap_event_name = events)
  hour_midpoints <- as_hms(c('07:30:00','08:30:00','09:30:00', '10:30:00', '11:30:00', '12:30:00', '13:30:00', '14:30:00', '15:30:00', '16:30:00', '17:30:00', '18:30:00', '19:30:00'))
  ema_plot$time <- hour_midpoints
  ema_plot <- left_join(ema_plot, ema)
  
  lims <- as_hms(c('07:00:00', '21:59:00'))
  hour_breaks = as_hms(c('07:00:00','08:00:00','09:00:00', '10:00:00', '11:00:00', '12:00:00', '13:00:00', '14:00:00', '15:00:00', '16:00:00', '17:00:00', '18:00:00', '19:00:00', '20:00:00', '21:00:00'))
  label_breaks = c("7am","","9am","","11am","","1pm","","3pm","","5pm","","7pm","","9pm")
  
  ema_plot <- ema_plot %>% select(time, hour_present, hour_nap, play_inside, nurse) %>% 
    pivot_longer(cols = hour_nap:nurse, names_to = "Activity", values_to = "Minutes")
  
  p1 <- ema_plot %>% mutate(Activity = factor(Activity, 
                                              levels=c("hour_nap", "play_inside", "nurse"),
                                              labels=c("Nap", "Play", "Eat/Drink/Nurse"))) %>% 
    ggplot(aes(x = time, y = Minutes, color = Activity)) + 
    geom_point(aes(x = time, y = hour_present), shape = "—", size = 5, color = "grey") + 
    geom_line() + geom_point() + 
    scale_x_time(breaks = hour_breaks, name = "", limits = lims, labels = label_breaks) + ylab("Minutes") + 
    theme(legend.position = "top",
          axis.title.x = element_blank(),
          axis.text.x = element_blank(),
          axis.ticks.x = element_blank()) + ylim(0,60) + 
    ggtitle(str_glue("ID {id}, Session {session}"))
  
  p2 <- sync_filt %>% mutate(pos = ifelse(pos == "Upright", "Standing", pos),
                             pos = factor(pos, levels=c("Supine", "Prone", "Sitting", "Standing", "Held"))) %>% 
    ggplot(aes(x = time_plot, y = 1, fill = pos)) + 
    geom_raster() + scale_fill_manual(values = pal, name = "") + 
    facet_wrap(~id, ncol = 1, scales = "free_x", strip.position = "left") +
    scale_x_time(breaks = hour_breaks, name = "", limits = lims, labels = label_breaks) + 
    theme(
      axis.title.y = element_blank(),
      axis.text.y = element_blank(),
      axis.ticks.y = element_blank(),
      strip.text = element_blank(),
      legend.position = "bottom"
    ) 
  
  p3 <- sync %>% mutate(cgpos = as.numeric(cgpos == "Upright")) %>% 
    ggplot(aes(x = time_plot, y = cgpos)) + geom_ma(n = 600, linetype = 1) + 
    theme(legend.position = "top",
          axis.title.x = element_blank(),
          axis.text.x = element_blank(),
          axis.ticks.x = element_blank()) + 
    scale_x_time(breaks = hour_breaks, name = "", limits = lims, labels = label_breaks) + 
    scale_y_continuous(name = "CG Up", breaks = c(0,1), labels = c("0%", "100%"), limits = c(0,1))
  
    fig <- p1/p3/p2 + plot_layout(heights = c(3,1,2))
  ggsave(plot = fig, filename = str_glue("/Volumes/padlab/study_sensorsinperson/data_processed/timelines/{id}_{session}.png",
                                         width = 10, height = 6))
}
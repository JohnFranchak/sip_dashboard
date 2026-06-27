library(tidyverse)
library(scales)
library(REDCapR)
library(hms)
library(patchwork)
library(tidyquant)
library(pins)

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

board <- board_folder("/Volumes/padlab/study_sensorsinperson/data_processed/datasets/")
data_version <- board %>% pin_meta("imu_raw_samples")
ds <- board %>% pin_read("imu_raw_samples") %>% 
  mutate(id_uni = paste(id, session, sep = "_"))
id_session <- unique(ds$id_uni)

sleep_tcds <- board %>% pin_read("sleep_tcds")

make_timeline <- function(i) {
  id <-strsplit(i, "_")[[1]][[1]]
  session <- strsplit(i, "_")[[1]][[2]]
  
  sync = ds %>% filter(id_uni == i)
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
  
  p2 <- sync_filt %>% 
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
  
  if (nrow(drop_na(sync, cgpos)) > 0) {
    p3 <- sync %>% mutate(cgpos = as.numeric(cgpos == "Standing"),
                          cgpos = ifelse(cg_exclude_period == 1, NA, cgpos),
                          group_id = consecutive_id(!is.na(cgpos))) %>% 
      ggplot(aes(x = time_plot, y = cgpos, group = group_id)) + geom_ma(n = 90, linetype = 1) + 
      theme(legend.position = "top",
            axis.title.x = element_blank(),
            axis.text.x = element_blank(),
            axis.ticks.x = element_blank()) + 
      scale_x_time(breaks = hour_breaks, name = "", limits = lims, labels = label_breaks) + 
      scale_y_continuous(name = "CG Up", breaks = c(0,1), labels = c("0%", "100%"), limits = c(0,1))
  }
  
  p4 <- sync %>% mutate(restraint = as.numeric(restraint == "Unrestrained"), 
                        restraint = ifelse(nap_period == 1 | exclude_period == 1, NA, restraint),
                        group_id = consecutive_id(!is.na(restraint))) %>% 
    ggplot(aes(x = time_plot, y = restraint, group = group_id)) +  
    geom_ma(n = 90, linetype = 1, color = "darkgreen", na.rm = FALSE) +    
    theme(legend.position = "top",
          axis.title.x = element_blank(),
          axis.text.x = element_blank(),
          axis.ticks.x = element_blank()) + 
    scale_x_time(breaks = hour_breaks, name = "", limits = lims, labels = label_breaks) + 
    scale_y_continuous(name = "Unrest.", breaks = c(0,1), labels = c("0%", "100%"), limits = c(0,1))
  
  p7 <- sync %>% mutate(inf_wear = as.numeric(wear_status == "worn"), 
                        cg_wear = as.numeric(cg_wear_status == "worn")) %>% 
    ggplot() + geom_ma(aes(x = time_plot, y = inf_wear), n = 150, color = "red") + 
    geom_ma(aes(x = time_plot, y = cg_wear), n = 150, linetype = 1, color = "blue") +
    theme(legend.position = "top",
          axis.title.x = element_blank(),
          axis.text.x = element_blank(),
          axis.ticks.x = element_blank()) + 
    scale_x_time(breaks = hour_breaks, name = "", limits = lims, labels = label_breaks) + 
    scale_y_continuous(name = "Wear", breaks = c(0,1), labels = c("0%", "100%"), limits = c(0,1))
  
  sleep <- sleep_tcds %>% filter(id == i)
  if (nrow(sleep) > 1) {
    sleep <- sleep %>% 
      filter(time_start >= min(sync$time), time_end <= max(sync$time)) %>% 
      mutate(time_plot = as_hms(time_start))
    
    p5 <- ggplot(sleep, aes(x = time_plot, y = sleep_prob)) + geom_line(linetype = 1, color = "red") + 
      theme(legend.position = "none",
            axis.title.x = element_blank(),
            axis.text.x = element_blank(),
            axis.ticks.x = element_blank()) + 
      scale_x_time(breaks = hour_breaks, name = "", limits = lims, labels = label_breaks) + 
      scale_y_continuous(name = "Sleep", breaks = c(0,1), labels = c("0%", "100%"), limits = c(0,1))
    
    p6 <- ggplot(sleep, aes(x = time_plot, y = cds_prob)) + geom_line(linetype = 1, color = "purple") + 
      theme(legend.position = "none",
            axis.title.x = element_blank(),
            axis.text.x = element_blank(),
            axis.ticks.x = element_blank()) + 
      scale_x_time(breaks = hour_breaks, name = "", limits = lims, labels = label_breaks) + 
      scale_y_continuous(name = "CDS", breaks = c(0,1), labels = c("0%", "100%"), limits = c(0,1))
    
    
    if (nrow(drop_na(sync, cgpos)) > 0) {
      fig <- p1/p5/p6/p3/p4/p7/p2 + plot_layout(heights = c(2,1,1,1,1,1,1))
    } else {
      fig <- p1/p5/p6/p4/p7/p2 + plot_layout(heights = c(2,1,1,1,1,1))
    }
  } else{
    if (nrow(drop_na(sync, cgpos)) > 0) {
      fig <- p1/p3/p4/p7/p2 + plot_layout(heights = c(3,2,2,2,2))
    } else {
      fig <- p1/p4/p7/p2 + plot_layout(heights = c(3,2,2,2))
    }
  }
  
  ggsave(plot = fig, filename = str_glue("/Volumes/padlab/study_sensorsinperson/data_processed/timelines/{id}_{session}.png",
                                         width = 10, height = 10), scale = 1.5)
  ggsave(plot = fig, filename = str_glue("timelines/{id}_{session}.png",
                                         width = 10, height = 10), scale = 1.5)
}

walk(id_session, make_timeline)

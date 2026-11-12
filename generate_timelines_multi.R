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

lims <- as_hms(c('07:00:00', '21:59:00'))
hour_breaks = as_hms(c('07:00:00','08:00:00','09:00:00', '10:00:00', '11:00:00', '12:00:00', '13:00:00', '14:00:00', '15:00:00', '16:00:00', '17:00:00', '18:00:00', '19:00:00', '20:00:00', '21:00:00'))
label_breaks = c("7am","","9am","","11am","","1pm","","3pm","","5pm","","7pm","","9pm")

board <- board_folder("/Volumes/padlab/study_sensorsinperson/data_processed/datasets/")

ds_multi <- board %>% pin_read("imu_raw_samples_multi")
ds_day_1 <- board %>% pin_read("imu_raw_samples") %>% filter(id %in% unique(ds_multi$id))

ds <- bind_rows(ds_day_1, ds_multi) %>% 
  mutate(id_uni = paste(id, session, sep = "_"),
         id_session_day = paste(id, session, day, sep = "_"))

ema_all <- board %>% pin_read("ema") %>% 
  bind_rows(pin_read(board, "ema_multi")) %>% 
  mutate(id_uni = paste(id, session, sep = "_"),
         id_session_day = paste(id, session, day, sep = "_")) %>% 
  filter(id %in% unique(ds_multi$id))

id_session <- unique(ds$id_uni)
id_session_day <- unique(ds$id_session_day)

make_timeline <- function(i) {
  id <-strsplit(i, "_")[[1]][[1]]
  session <- strsplit(i, "_")[[1]][[2]]
  
  sync = ds %>% filter(id_uni == i)
  sync_filt <- sync %>% filter(nap_period == 0, exclude_period == 0)
  recording_days <- unique(sync$day)

  ema_temp <- ema_all %>% filter(id_uni == i) %>% rename(hour = time)
  
  plot_day <- function(d) {
    ema_plot <- tibble(hour = c(800,  900, 1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900, 2000),
                       time = c('07:30:00','08:30:00','09:30:00', '10:30:00', '11:30:00', '12:30:00', '13:30:00', '14:30:00', '15:30:00', '16:30:00', '17:30:00', '18:30:00', '19:30:00'))
    ema_plot <- left_join(ema_plot, filter(ema_temp, day == d))
    
    ema_plot <- ema_plot %>% select(time, hour_present, hour_nap, play_inside, nurse) %>% 
      pivot_longer(cols = hour_nap:nurse, names_to = "Activity", values_to = "Minutes") %>% 
      mutate(time = as_hms(time))
    
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
            axis.ticks.x = element_blank()) + ylim(0,60) 
    if (d == 1) p1 <- p1 + ggtitle(str_glue("ID {id}, Session {session}"))
    if (d > 1) p1 <- p1 + theme(axis.title.y = element_blank(), axis.text.y = element_blank(), axis.ticks.y = element_blank())
      
    
    p2 <- sync_filt %>% filter(day == d) %>% 
      ggplot(aes(x = time_plot, y = 1, fill = pos)) + 
      geom_raster() + scale_fill_manual(values = pal, name = "") + 
      facet_wrap(~id, ncol = 1, scales = "free_x", strip.position = "left") +
      scale_x_time(breaks = hour_breaks, name = str_glue("Day {d}"), limits = lims, labels = label_breaks) + 
      theme(
        axis.title.y = element_blank(),
        axis.text.y = element_blank(),
        axis.ticks.y = element_blank(),
        strip.text = element_blank(),
        legend.position = "bottom"
      ) 
    if (d > 1) p2 <- p2 + theme(axis.title.y = element_blank(), axis.text.y = element_blank(), axis.ticks.y = element_blank())
    
    if (nrow(drop_na(sync, cgpos)) > 0) {
      p3 <- sync %>% filter(day == d) %>% 
        mutate(cgpos = as.numeric(cgpos == "Standing"),
                            cgpos = ifelse(cg_exclude_period == 1, NA, cgpos),
                            group_id = consecutive_id(!is.na(cgpos))) %>% 
        ggplot(aes(x = time_plot, y = cgpos, group = group_id)) + geom_ma(n = 90, linetype = 1) + 
        theme(legend.position = "top",
              axis.title.x = element_blank(),
              axis.text.x = element_blank(),
              axis.ticks.x = element_blank()) + 
        scale_x_time(breaks = hour_breaks, name = "", limits = lims, labels = label_breaks) + 
        scale_y_continuous(name = "CG Up", breaks = c(0,1), labels = c("0%", "100%"), limits = c(0,1))
      if (d > 1) p3 <- p3 + theme(axis.title.y = element_blank(), axis.text.y = element_blank(), axis.ticks.y = element_blank())
    }
    
    
    p4 <- sync %>%  filter(day == d) %>% 
      mutate(restraint = as.numeric(restraint == "Unrestrained"), 
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
    if (d > 1) p4 <- p4 + theme(axis.title.y = element_blank(), axis.text.y = element_blank(), axis.ticks.y = element_blank())
    
    if (nrow(drop_na(sync, cgpos)) > 0) {
      fig <- p1/p3/p4/p2 + plot_layout(heights = c(3,2,2,2))
    } else {
      fig <- p1/p4/p2 + plot_layout(heights = c(3,2,2))
    }
    return(fig)
  }
  day_plots <- map(recording_days, plot_day)
  fig <- wrap_plots(day_plots,nrow = 1, guides = "collect", axes = "collect_y", axis_titles = "collect_y")  & 
    theme(legend.position = "bottom")
  w = length(recording_days) * 4
  ggsave(plot = fig, filename = str_glue("/Volumes/padlab/study_sensorsinperson/data_processed/timelines_multi/{id}_{session}.png"), 
                                         width = w, height = 3, scale = 1.5)
  ggsave(plot = fig, filename = str_glue("/Users/johnfranchak/Documents/GitHub/sip_dashboard/timelines_multi/{id}_{session}.png"),
                                         width = w, height = 3, scale = 1.5)
}

walk(id_session, make_timeline)

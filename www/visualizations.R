
### COMMON INFORMATION FOR ALL THE VISUALIZATION FUNCTIONS ####
# -------------------------------------------------------------------------------------------------------
# interactive argument is used to toggle between interactive plotly plots and normal static ggplots
# the information showed in the tooltip box on mouse hover is included as dummy aesthetics label1, label2 ..
# the above causes new versions of ggplot2 to throw warnings, which can be ignored
# shiny also displays warnings about excplicit widget IDs when working with plotly, but these can be ignored as well
#-------------------------------------------------------------------------------------------------------

# Combines two matrices
coalesce<-function(...) {
  x<-lapply(list(...), function(z) {if (is.factor(z)) as.character(z) else z})
  m<-is.na(x[[1]])
  i<-2
  while(any(m) & i<=length(x)) {
    if ( length(x[[i]])==length(x[[1]])) {
      x[[1]][m]<-x[[i]][m]
    } else if (length(x[[i]])==1) {
      x[[1]][m]<-x[[i]]
    } else {
      stop(paste("length mismatch in argument",i," - found:", length( x[[i]] ),"expected:",length( x[[1]] ) ))
    }
    m<-is.na(x[[1]])
    i<-i+1
  }
  return(x[[1]])
}

# Strip dataset names from variables
strip_ds <- function(ds_var, datasets){
  ds_var <- as.character(ds_var)
  datasets <- as.character(unique(datasets))
  for(dataset in datasets){
    ds_var <- gsub(dataset, "", ds_var)
  }
  ds_var
}

# Transform a data frame to lower triangular form for heat map
# Possibility for hierarchical clustering
# Both input and output in long format
transform_to_lowertri <- function(dframe,effect_type,clustering){
  dat <- dframe %>% select(DS_Variable1,DS_Variable2,Effect)
  dat$DS_Variable1 <- as.character(dat$DS_Variable1)
  dat$DS_Variable2 <- as.character(dat$DS_Variable2)
  
  # This makes sure all the variables will be included in both axes
  vars <- c(dat$DS_Variable1,dat$DS_Variable2) %>% unique()
  x <- setdiff(vars,dat$DS_Variable1)
  y <- setdiff(vars,dat$DS_Variable2)
  append_len <- max(length(x),length(y))
  append_df <- data.frame(DS_Variable1 = c(x,rep(NA, append_len - length(x))),
                          DS_Variable2 = c(y,rep(NA, append_len - length(y))),
                          Effect = NA)
  dat <- rbind(dat,append_df)
  
  # Converting data into wide format and tidying data
  dat_w <- dat %>% spread(DS_Variable2,Effect) %>% filter(!is.na(DS_Variable1))
  rownames(dat_w) <- dat_w$DS_Variable1
  dat_w <- dat_w %>% select(-DS_Variable1)
  dat_w <- dat_w[rownames(dat_w)!="NA",! colnames(dat_w) %in% c("NA","<NA>")] #one of the columns or rows is named NA
  dat_w <- dat_w[rev(order(names(dat_w))),rev(order(names(dat_w)))] #this makes the image lie on the lower triangular
  
  # dat_w only has one-directional interactions
  # for example, metformine vs morphine = 1.09, but morphine vs metformine = NA
  # transpose values are added to make the matrix symmetrical
  dat_w_t <- data.frame(t(dat_w))
  dat_w_whole <- coalesce(dat_w,dat_w_t)
  
  # Order rows and columns by hierarchical clustering
  if (clustering){
    dat_w_whole_zeros <- dat_w_whole
    if (effect_type %in% c("OR","FC")){
      dat_w_whole_zeros[is.na(dat_w_whole_zeros)] <- 1
    }
    else{
      dat_w_whole_zeros[is.na(dat_w_whole_zeros)] <- 0
    }
    hc <- hclust(dist(dat_w_whole_zeros))
    dat_w_whole <- dat_w_whole[hc$order,hc$order]
  }
  
  # Only half of the associations are needed for plotting
  dat_w_whole[upper.tri(dat_w_whole)] <- NA
  # Diagonal should be included in the plot
  
  # Melt back to long format for ggplot2
  dat_w_whole$DS_Variable1 <- rownames(dat_w_whole)
  dat_l <- gather(dat_w_whole,DS_Variable2, Effect, -DS_Variable1)
  
  # Joining other columns from original dframe
  dat_l$DS_Variable2 <- as.character(dat_l$DS_Variable2)
  dat_l_orig <- dat_l
  # The order of Variable1 and 2 has changed for some associations, so two joins are required
  combined1 <- inner_join(dat_l, dframe, by = c("DS_Variable1","DS_Variable2","Effect"))
  combined2 <- inner_join(dat_l,dframe,by = c("DS_Variable1" = "DS_Variable2","DS_Variable2" = "DS_Variable1","Effect"))
  dat_l <- rbind(combined1,combined2)%>%
    dplyr::distinct() # Remove duplicated associations with same DS_Variable1 and DS_Variable2
  
  # Fix the order of variable1 and 2
  dat_l$Variable1 <- strip_ds(dat_l$DS_Variable1, dat_l$Dataset)
  dat_l$Variable2 <- strip_ds(dat_l$DS_Variable2, dat_l$Dataset)
  
  # Setting the factor levels to correctly draw the heatmap
  # This ensures the tiles are plotted in correct order to make a lower triangular heat map
  dat_l$DS_Variable1 <- dat_l$DS_Variable1 %>% 
    factor(levels = rev(rownames(dat_w_whole)))
  dat_l$DS_Variable2 <- dat_l$DS_Variable2 %>%
    factor(levels = rownames(dat_w_whole))
  
  dat_l
}

# Return a categorical variable based on Effects
# This can be used for discrete color scale with 5 colours
# Levels are low, semi-low, zero, semi_high and high
to_levels <- function(effect, type){
  if(type %in% c("OR","FC")){
    effect <- log2(effect)
  }
  level <- rep(NA, length(effect))
  min_ <- min(effect)
  max_ <- max(effect)
  if(min_ < 0 & max_ > 0){
    zero_limit <- 0.2* min(abs(min_), abs(max_))
  }
  if(max_ < 0){
    zero_limit <- 0.2*abs(min_)
  }
  if(min_ > 0){
    zero_limit <- 0.2*max_
  }
  level[effect >= -zero_limit & effect <= zero_limit] <- paste(signif(-zero_limit, digits = 2),"...",signif(zero_limit, digits = 2))
  min_half <- (min_ - zero_limit)/2
  level[effect >= min_half & effect < -zero_limit] <- paste(signif(min_half, digits = 2),"...",signif(-zero_limit, digits = 2))
  level[effect < min_half] <- paste("<", signif(min_half, digits = 2))
  max_half <- (max_ + zero_limit)/2
  level[effect > zero_limit & effect <= max_half] <- paste(signif(zero_limit, digits = 2),"...",signif(max_half, digits = 2))
  level[effect > max_half] <- paste(">", signif(max_half, digits = 2))
  
  level <- factor(level, levels = c(paste(">", signif(max_half, digits = 2)),
                                    paste(signif(zero_limit, digits = 2),"...",signif(max_half, digits = 2)),
                                    paste(signif(-zero_limit, digits = 2),"...",signif(zero_limit, digits = 2)),
                                    paste(signif(min_half, digits = 2),"...",signif(-zero_limit, digits = 2)),
                                    paste("<", signif(min_half, digits = 2))))
  
  list(levels = level,
       breakpoints = signif(c(min_half,zero_limit,max_half),digits = 2))
}

# Get a lower triangular heat map
# clustering = TRUE orders rows and columns by hierarchical clustering
get_heatmap_lowertri <- function(dframe,effect_type,clustering, interactive){
  # Remove missing variable labels
  dframe <- dframe %>% 
    filter(!is.na(Variable1), !is.na(Variable2)) %>%
    mutate(DS_Variable1 = paste(Dataset, Variable1, sep = ""), DS_Variable2 = paste(Dataset, Variable2, sep = ""))
  # Transform to lower triangular and cluster if clustering is TRUE
  dframe_lowertri <- transform_to_lowertri(dframe,effect_type,clustering)
  effect_levels <- to_levels(dframe_lowertri$Effect, effect_type)
  breakpoints <- effect_levels$breakpoints
  dframe_lowertri$effect_level <- effect_levels$levels
  
  # Creating the ggplot object
  if(interactive){
    p <- ggplot(dframe_lowertri,aes(x = DS_Variable1, y = DS_Variable2, label1 = Dataset, label2 = Variable1, label3 = Variable2, label4 = Description1, label5 = Description2,
                          label6 = Effect, label7 = P_FDR, label8 = N))
  }
  else{
    p <- ggplot(dframe_lowertri, aes(x = DS_Variable1, y = DS_Variable2))
  }
  if(effect_type %in% c("OR","FC")){
    legend_label <- paste("log2(",effect_type,")", sep = "")
  }
  else{
    legend_label <- effect_type
  }
  x_labels <- strip_ds(levels(dframe_lowertri$DS_Variable1), dframe_lowertri$Dataset)
  y_labels <- strip_ds(levels(dframe_lowertri$DS_Variable2), dframe_lowertri$Dataset)
  
  p <- p +
    geom_tile(aes(fill = effect_level)) +
    theme_minimal() +
    theme(panel.grid.major = element_blank(),
          panel.grid.minor = element_blank(),
          axis.text.x = element_text(angle = 90)) +
    scale_fill_manual(name = legend_label,
                      values = c("#CA0020","#F4A582","#F0F0F0","#92C5DE","#0571B0"),
                      breaks = levels(dframe_lowertri$effect_level)) +
    scale_x_discrete(drop = FALSE, labels = x_labels) +
    scale_y_discrete(drop = FALSE, labels = y_labels) +
    xlab("") + ylab("")
  
  if (interactive){
    ggplotly(p,tooltip = paste("label",1:8, sep = ""))
  }
  else{
    vars1 <- levels(dframe_lowertri$DS_Variable1)
    vars2 <- levels(dframe_lowertri$DS_Variable2)
    indx <- seq(1,length(vars1),length.out = 40)
    if(length(vars1) > 80){
      p <- p +
        scale_x_discrete(breaks = vars1[indx], labels = x_labels[indx], drop=FALSE) +
        scale_y_discrete(breaks = vars2[indx], labels = y_labels[indx], drop=FALSE)
    }
    p
  }
}

# Volcano plot with double filtering
# Input:  data frame with effect, p_fdr and point labels
#         string containing the effect type
#         varnum
#         double_filter: boolean telling if double filtering is enabled (TRUE or FALSE)
#         df_p_lim: double filtering limit for p-value
#         fdr: boolean, TRUE: p-limit is for P_FDR FALSE: p-limit is for P
#         df_effect_lim: double filtering limit for effect
#         eff_limit_log2: boolean, TRUE: limit is for log2(effect), FALSE, limit is for raw effect
volcanoplot <- function(dframe,effect_type,varnum,double_filter,
                             df_p_lim = NULL, fdr = NULL, df_effect_lim = NULL, eff_limit_log2 = NULL,
                             shape, interactive = FALSE){
  # The points with p_fdr = 0 would not be plotted,
  # so they are replaced with 1e-300
  dframe$P <- lapply(dframe$P, function(x){if(x == 0) x = 1e-300 else x}) %>% unlist()
  # Create column for double filtering coloring
  if (double_filter){
    if (eff_limit_log2){
      df_effect_lim <- as.numeric(df_effect_lim)
    }
    else{
      df_effect_lim <- log2(as.numeric(df_effect_lim))
    }
    if (fdr){
      dframe <- dframe %>% mutate(df = factor(P_FDR < df_p_lim & abs(log2(Effect)) > df_effect_lim, levels = c(TRUE, FALSE)))
    }
    else{
      dframe <- dframe %>% mutate(df = factor(P < df_p_lim & abs(log2(Effect)) > df_effect_lim, levels = c(TRUE, FALSE)))
    }
    coloring <- "df"
  }
  else{
    coloring <- NULL
  }
  # OR and FC require log2 transformation before plotting
  # Set x axis labels and limits for symmetrical plot in terms of zero
  if (effect_type %in% c("OR","FC")){
    x_axis <- "log2(Effect)"
    x_label <- paste("log2(",effect_type,")",sep = "")
    x_lims <- c(-max(abs(log2(dframe$Effect))),max(abs(log2(dframe$Effect))))
  }
  else{
    x_axis <- "Effect"
    x_label <- effect_type
    x_lims <- c(-max(abs(dframe$Effect)),max(abs(dframe$Effect)))
  }
  
  if (varnum == 1){
    p <- ggplot(dframe, aes(label1 = Dataset, label2 = Variable1, label3 = Description1,
                            label4 = Effect, label5 = P_FDR, label6 = N))
  }
  if(varnum == 2){
    p <- ggplot(dframe, aes(label1 = Dataset, label2 = Variable1, label3 = Variable2, label4 = Description1,
                            label5 = Description2, label6 = Effect, label7 = P_FDR, label8 = N))
  }
  if(shape){
    point_shape <- "Dataset"
  }
  else{
    point_shape <- NULL
  }
  p <- p +
    geom_point(aes_string(x = x_axis, y = "-log10(P)", color = coloring, shape = point_shape)) +
    scale_colour_manual(breaks = c("TRUE","FALSE"),values = c("TRUE" = "red", "FALSE" = "grey"),
                        guide = guide_legend(title = NULL)) +
    xlim(x_lims[1],x_lims[2]) +
    xlab(x_label) +
    theme_minimal()
  # Add labels to plotly tooltip
  if(interactive){
    if (varnum == 1){
      p <- ggplotly(p, tooltip = paste("label",1:6,sep=""))
    }
    if(varnum == 2){
      p <- ggplotly(p, tooltip = paste("label",1:8,sep=""))
    }
  }
  p
}

# Normal Q_Q plot with confidence bands
# This function is a modified version of the one presented in
# https://gist.github.com/rentrop/d39a8406ad8af2a1066c
qq_normal <- function(dframe,effect_type,varnum,ci = 0.95, color_col = NULL, color_type = NULL, interactive = TRUE){
  
  x <- dframe$Effect
  dframe <- dframe %>% arrange(Effect)
  
  if (effect_type %in% c("OR","FC")){
    x <- log2(x)
    ylabel <- paste("log2(",effect_type,")",sep = "")
  }
  else{
    ylabel <- effect_type
  }
  #Missing values are removed and the effect vector is ordered
  x <- na.omit(x)
  n <- length(x)
  P <- ppoints(length(x))
  dframe$ord.x <- sort(x, decreasing = FALSE)
  dframe$z <- qnorm(P)
  # The coefficients for the line
  Q.x <- quantile(dframe$ord.x, c(0.25, 0.75))
  Q.z <- qnorm(c(0.25, 0.75))
  b <- diff(Q.x)/diff(Q.z)
  coef <- c(Q.x[1] - b * Q.z[1], b)
  # The values for the confidence band
  zz <- qnorm(1 - (1 - ci)/2)
  SE <- (coef[2]/dnorm(dframe$z)) * sqrt(P * (1 - P)/n)
  fit.value <- coef[1] + coef[2] * dframe$z
  dframe$upper <- fit.value + zz * SE
  dframe$lower <- fit.value - zz * SE
  # Grid and background color is omited to boost performance,
  # the line and the confidence band is added
  if(!is.null(color_col)){
    if(color_type == "Discrete"){
      dframe[,color_col] <- as.factor(dframe[,color_col])
    }
  }
  p <- ggplot(dframe, aes(x=z, y=ord.x)) +
    theme(panel.grid.major = element_blank(), panel.grid.minor = element_blank(),
          panel.background = element_blank(), axis.line = element_line(colour = "black")) +
    xlab("Normal quantiles") + ylab(ylabel) +
    geom_abline(intercept = coef[1], slope = coef[2], color = "red") +
    geom_ribbon(aes(ymin = lower, ymax = upper), alpha=0.2) +
    scale_fill_gradient(low = "grey40", high = "grey40")
  
  if(!is.null(color_col) & class(dframe[, color_col]) %in% c("character", "factor") & length(unique(dframe[, color_col])) <= 12){
    p <- p +
      scale_color_brewer(type = "qual", palette = "Paired")
  }
  # Interactivity can be disabled
  if (interactive){
    if (varnum == 1){
      p <- p + geom_point(aes_string(color = color_col, label1 = "Dataset", label2 = "Variable1", label3 = "Description1",
                              label4 = "Effect", label5 = "P_FDR", label6 = "N"))
      p <- ggplotly(p, tooltip = paste("label",1:6,sep=""))
    }
    if(varnum == 2){
      p <- p + geom_point(aes_string(color = color_col, label1 = "Dataset", label2 = "Variable1", label3 = "Variable2", label4 = "Description1",
                              label5 = "Description2", label6 = "Effect", label7 = "P_FDR", label8 = "N"))
      p <- ggplotly(p, tooltip = paste("label",1:8,sep=""))
    } 
  }
  else{
    p <- p + geom_point()
  }
  p
}

# Q-Q plot of p-values versus expected p-values with confidence bands
qq_pvalues <- function(dframe, varnum, ci = 0.95, color_col = NULL, color_type = NULL, interactive = TRUE){
  dframe <- dframe %>% arrange(P)
  # The points with p_fdr = 0 would not be plotted,
  # so they are replaced with 1e-300
  dframe$P <- lapply(dframe$P, function(x){if(x == 0) x = 1e-300 else x}) %>% unlist()
  
  # Calculate expected p-values
  n <- nrow(dframe)
  dframe$observed <- -log10(dframe$P)
  dframe$expected <- -log10(1:n/n)
  dframe$cupper <- -log10(qbeta(ci,     1:n, n - 1:n + 1))
  dframe$clower <- -log10(qbeta(1- ci,  1:n, n - 1:n + 1))
  
  if(!is.null(color_col)){
    if(color_type == "Discrete"){
      dframe[,color_col] <- as.factor(dframe[,color_col])
    }
  }
  
  # Create ggplot object
  p <- ggplot(dframe, aes(x=expected, y=observed)) +
    theme(panel.grid.major = element_blank(), panel.grid.minor = element_blank(),
          panel.background = element_blank(), axis.line = element_line(colour = "black")) +
    geom_abline(intercept = 0, slope = 1, color = "red") +
    geom_ribbon(aes(x = expected, ymin = clower, ymax = cupper), alpha = 0.2) +
    xlab("Expected - log10(P)") +
    ylab("Observed - log10(P)")
  
  if(!is.null(color_col) & class(dframe[, color_col]) %in% c("character", "factor") & length(unique(dframe[, color_col])) <= 12){
    p <- p +
      scale_color_brewer(type = "qual", palette = "Paired")
  }
  
  if (interactive){
    if (varnum == 1){
      p <- p + geom_point(aes_string(color = color_col, label1 = "Dataset", label2 = "Variable1", label3 = "Description1",
                                     label4 = "Effect", label5 = "P_FDR", label6 = "N"))
      p <- ggplotly(p, tooltip = paste("label",1:6,sep=""))
    }
    if(varnum == 2){
      p <- p + geom_point(aes_string(color = color_col, label1 = "Dataset", label2 = "Variable1", label3 = "Variable2", label4 = "Description1",
                                     label5 = "Description2", label6 = "Effect", label7 = "P_FDR", label8 = "N"))
      p <- ggplotly(p, tooltip = paste("label",1:8,sep=""))
    } 
  }
  else{
    p <- p + geom_point()
  }
  p
}

# Lady Manhattan plot
# The y-axis of a traditional Manhattan plot, -log10(p) is multiplied by the sign of the effect
# The plot can be colored by chosen column
lady_manhattan_plot <- function(dframe,effect_type,varnum, interactive = TRUE, color_col = NULL, color_type = NULL){
  # For OR and FC, use log2 effect
  if(effect_type %in% c("OR","FC")){
    dframe <- dframe %>% mutate(Y = -log10(P) * sign(log2(Effect)))
    y_label <- paste("-log10(P) * sign(log2(", effect_type ,"))",sep="")
  }
  else{
    dframe <- dframe %>% mutate(Y = -log10(P) * sign(Effect))
    y_label <- paste("-log10(P) * sign(", effect_type ,")",sep="")
  }
  # For datasets with interactions, the combinations of variables are used as x-axis
  if(varnum == 1){
    x_axis <- "Variable1"
    x_label <- "Variable"
    x_breaks <- sort(dframe$Variable1)[seq(1,nrow(dframe),length.out = 40)]
  }
  if(varnum == 2){
    dframe <- dframe %>% mutate(X = paste(Variable1,Variable2,sep="_x_"))
    x_axis <- "X"
    x_label <- "Variables"
    x_breaks <- sort(dframe$X)[seq(1,nrow(dframe),length.out = 40)]
  }
  # Color is discretised by changing the coloring column to factor
  if(!is.null(color_col)){
    if(color_type == "Discrete"){
      dframe[,color_col] <- as.factor(dframe[,color_col])
    }
  }
  
  p <- ggplot(dframe, aes_string(x = x_axis,y = "Y", color = color_col)) +
    scale_x_discrete(breaks = x_breaks) +
    theme_minimal() +
    theme(panel.grid.major = element_blank(),
          panel.grid.minor = element_blank(),
          axis.text.x = element_text(angle = 90)) +
    labs(x = x_label, y = y_label)
  
  # Use color scale from colorbrewer when possible
  if(!is.null(color_col) & class(dframe[, color_col]) %in% c("character", "factor") & length(unique(dframe[, color_col])) <= 12){
    p <- p +
      scale_color_brewer(type = "qual", palette = "Paired")
  }
  
  if (interactive){
    if (varnum == 1){
      p <- p + geom_point(aes(label1 = Dataset, label2 = Variable1, label3 = Description1,
                              label4 = Effect, label5 = P_FDR, label6 = N))
      p <- ggplotly(p, tooltip = paste("label",1:6,sep=""))
    }
    if(varnum == 2){
      p <- p + geom_point(aes(label1 = Dataset, label2 = Variable1, label3 = Variable2, label4 = Description1,
                              label5 = Description2, label6 = Effect, label7 = P_FDR, label8 = N))
      p <- ggplotly(p, tooltip = paste("label",1:8,sep=""))
    } 
  }
  else{
    p <- p + geom_point()
  }
  p
}
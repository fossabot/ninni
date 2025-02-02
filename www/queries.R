
# Read database info from .congif file
read_db_info <- function(config_file){
  df <- read.table(config_file)
  
  l <- as.list(as.character(df$V2))
  names(l) <- df$V1
  l
}

# Get associations from the database matching search
# User can searh by dataset label, metadata tags or variable keywords
# Return a list with following elements:
# - dframe: the associations table query object
# - datasets: the datasets data frame
# - varnum: greatest number of variables per association
# - effect_type: effect type of datasets, "Multiple" in case of variation
get_associations <- function(pool,ds_labels,var_keywords,metadata_tags){
  assocs_tbl <- pool %>% tbl("associations")
  ds_tbl <- pool %>% tbl("datasets")
  
  # Filter dataset table by metadata tags and/or dataset labels
  if(length(metadata_tags) | length(ds_labels)){
    ds_tbl <- filter_datasets(pool, ds_tbl, metadata_tags, ds_labels)
    assocs_tbl <- asssocs_tbl <- assocs_tbl %>%
      semi_join(ds_tbl, by = c("dataset_id" = "id"))
  }
  # Keep only variables matching keywords
  if(var_keywords != ""){
    tmp_list <- filter_associations_by_variable(pool,assocs_tbl,ds_tbl,var_keywords)
    assocs_tbl <- tmp_list[[1]]
    ds_tbl <- tmp_list[[2]]
  }
  
  # Determine effect type and number of variables per association
  ds_df <- collect(ds_tbl)
  varnum <- ds_df$varnum
  effect_type <-ds_df$effect_type
  if(any(ds_df$varnum == 2)){
    varnum <- 2
  }
  else{
    varnum <- 1
  }
  if(length(unique(ds_df$effect_type)) == 1){
    effect_type <- unique(ds_df$effect_type)
  }
  else{
    effect_type <- "Multiple" # Multiple means the associations can't be plotted together
  }
  
  return(list(dframe = assocs_tbl, datasets = ds_df, varnum = varnum, effect_type = effect_type))
}

# Filter datasets by metadata tags and labels
filter_datasets <- function(pool, ds_tbl, metadata_tags, ds_labels){
  # Filter by metadata tag
  if(length(metadata_tags)){
    
    if(length(metadata_tags) == 1){
      meta_tbl <- pool %>% tbl("datasetmetadata") %>%
        filter(label == metadata_tags)
    }
    else{
      meta_tbl <- pool %>% tbl("datasetmetadata") %>%
        filter(label %in% metadata_tags)
    }
    ds_to_meta_tbl <- pool %>% tbl("datasettometadata") %>%
      semi_join(meta_tbl,by=c("datasetmetadata_id" = "id"))
    ds_tbl <- ds_tbl %>%
      semi_join(ds_to_meta_tbl,by=c("id"="dataset_id"))
  }
  
  #Filter by dataset label
  if(length(ds_labels > 0)){
    if(length(ds_labels) == 1){
      ds_tbl <- ds_tbl %>% filter(label == ds_labels)
    }
    else{
      ds_tbl <- ds_tbl %>% filter(label %in% ds_labels)
    }
  }
  
  ds_tbl
}

# Filter association table, keeping only variables matching keywords
filter_associations_by_variable <- function(pool,assocs_tbl,ds_tbl,var_keywords){
  keywords <- var_keywords %>% strsplit(split=",") %>% unlist()
  
  var_tbl <- filtered_var_tbl(pool, keywords)
  
  assoc_to_var_tbl <- pool %>% tbl("associationtovariable") %>%
    semi_join(var_tbl,by=c("variable_id" = "id"))
  assocs_tbl <- assocs_tbl %>%
    semi_join(assoc_to_var_tbl,by = c("id" = "association_id"))
  ds_tbl <- ds_tbl %>%
    semi_join(assocs_tbl,by=c("id" = "dataset_id"))
  
  return(list(assocs_tbl,ds_tbl))
}

# Get variable table filtered by keywords
filtered_var_tbl <- function(pool, var_keywords){
  # Get variable table as data frame
  var_df <- pool %>% tbl("variables") %>% collect()
  
  # Get all variables where either label or description matches keywords
  var_df_label <- filter_by_keyword(var_df,"label",var_keywords)
  var_df_description <- filter_by_keyword(var_df,"description",var_keywords)
  var_df <- union(var_df_label, var_df_description)
  
  accepted_labels <- var_df$label
  
  if(!length(accepted_labels))
    stop("No variables matching the search found in the database")
  
  if(length(accepted_labels) == 1){
    var_tbl <- pool %>% tbl("variables") %>% filter(label == accepted_labels)
  }
  else{
    var_tbl <- pool %>% tbl("variables") %>% filter(label %in% accepted_labels)
  }
  
  var_tbl
}

# Get all the datasets in the database with their metadata tags
get_datasets <- function(pool){
  # Get dataset metadata
  meta_tbl <- pool %>% tbl("datasetmetadata")
  ds_to_meta_tbl <- pool %>% tbl("datasettometadata") %>%
    inner_join(meta_tbl,by=c("datasetmetadata_id" = "id")) %>%
    collect() %>%
    # Put all metadata tags from one dataset into one row
    group_by(dataset_id) %>%
    mutate(Metadata_labels = paste(label, collapse=","), Metadata_descriptions = paste(description, collapse=",")) %>%
    ungroup() %>%
    select(-label,-description, -id, -datasetmetadata_id) %>%
    distinct()
  # Join metadata to dataset table and rename columns
  ds_tbl <- pool %>% tbl("datasets") %>%
    collect() %>%
    left_join(ds_to_meta_tbl,by=c("id" = "dataset_id")) %>%
    dplyr::select(-id) %>%
    rename(Label = label, Description = description, Number_of_variables = varnum,
           Effect_type = effect_type, Number_of_associations = rowcount)
  ds_tbl
}

# Get the metavariables matching associations
get_metavariables <- function(pool,assocs_tbl){
  
  final_tbl <- NULL
  
  # Get numeric metavariables
  numval_tbl <- pool %>% tbl("numval") %>%
    semi_join(assocs_tbl, by = c("association_id" = "id"))
  metavar_tbl <- pool %>% tbl("metavariables") %>%
    semi_join(numval_tbl, by = c("id" = "metavariable_id")) %>% collect()
  
  # Add metavar as column name and values as column elements to data frame
  if(nrow(collect(numval_tbl))){
    final_tbl <- data.frame()
    for (i in 1:nrow(metavar_tbl)){
      numval_tmp <- collect(numval_tbl) %>% filter(metavariable_id == metavar_tbl$id[i]) %>% select(association_id,value)
      if(nrow(final_tbl) == 0){
        final_tbl <- numval_tmp
        colnames(final_tbl) <- c("association_id",metavar_tbl$label[i])
      }
      else{
        final_tbl <- left_join(final_tbl,numval_tmp,by="association_id")
        colnames(final_tbl)[i+1] <- metavar_tbl$label[i]
      }
    }
  }
  
  #Get character metavariables
  strval_tbl <- pool %>% tbl("strval") %>%
    semi_join(assocs_tbl, by = c("association_id" = "id"))
  metavar_tbl <- pool %>% tbl("metavariables") %>%
    semi_join(strval_tbl, by = c("id" = "metavariable_id")) %>% collect()
  
  # Add metavar as column name and values as column elements to data frame
  if(nrow(collect(strval_tbl))){
    for (i in 1:nrow(metavar_tbl)){
      strval_tmp <- collect(strval_tbl) %>% filter(metavariable_id == metavar_tbl$id[i]) %>% select(association_id,value)
      if(nrow(final_tbl) == 0){
        final_tbl <- strval_tmp
        colnames(final_tbl) <- c("assciation_id",metavar_tbl$label[i])
      }
      else{
        final_tbl <- left_join(final_tbl,strval_tmp,by="association_id")
        colnames(final_tbl)[ncol(final_tbl)] <- metavar_tbl$label[i]
      }
    }
  }
  
  final_tbl
}
# Joins the variables and metavariables to the associations table
# Returns COLLECTED local data frame
join_variables <- function(pool,assocs_tbl,ds_df){
  
  metavar_tbl <- get_metavariables(pool,assocs_tbl)
  
  # Searches the variables connected to the associations and joins them to the assocs_tbl
  assoc_to_var_tbl <- pool %>% tbl("associationtovariable") %>% 
    semi_join(assocs_tbl, by = c("association_id" = "id"))
  var_tbl <- pool %>% tbl("variables") %>% 
    inner_join(assoc_to_var_tbl, by = c("id" = "variable_id"))
  assocs_tbl <- assocs_tbl %>%
    rename(association_id = id) %>%
    left_join(var_tbl,by = "association_id")
  
  assocs_df <- collect(assocs_tbl)
  dataset_ids <- sort(unique(assocs_df$dataset_id))
  
  assocs_df_edited <- data.frame()
  # Join variables separately for each original dataset
  # Joining method depends on varnum
  for(ds_id in dataset_ids){
    assocs_df_tmp <- assocs_df %>% filter(dataset_id == ds_id)
    varnum <- ds_df[ds_df$id == ds_id, "varnum"]$varnum
    assocs_df_tmp$dataset_label <- as.character(ds_df[ds_df$id == ds_id, "label"])
    assocs_df_tmp$effect_type <- as.character(ds_df[ds_df$id == ds_id, "effect_type"])
    
    # Removes unnecessary columns
    if (varnum == 1){
      assocs_df_tmp <- assocs_df_tmp %>%
        select(-id.x,-id.y, -dataset_id) %>%
        collect() %>%
        rename(Variable1 = label, Description1 = description)
    }
    # Removes unnecessary columns and combines the rows of same association
    # (Before this the table had two rows with the same association information, but only one variable each)
    if (varnum == 2){
      assocs_df_tmp <- assocs_df_tmp %>%
        select(-id.x,-id.y, -dataset_id)
      #incProgress(0.2,message = "Processing dataset")
      assocs_df_tmp <- assocs_df_tmp %>%
        group_by(association_id) %>%
        dplyr::mutate(var_labels = paste(label[1],label[2],sep = ";"),var_descriptions = paste(description[1],description[2],sep = ";")) %>%
        dplyr::ungroup() %>%
        dplyr::select(-description,-label) %>%
        dplyr::distinct() %>% 
        tidyr::separate(var_labels, c("Variable1","Variable2"),sep = ";") %>%
        tidyr::separate(var_descriptions, c("Description1","Description2"), sep = ";")  
    }
    # Join metavariables
    if(!is.null(metavar_tbl)){
      assocs_df_tmp <- left_join(assocs_df_tmp,metavar_tbl,by="association_id")
    }
    assocs_df_edited <- bind_rows(assocs_df_edited, assocs_df_tmp)
  }
  assocs_df <- make_pretty(assocs_df_edited, ds_df$varnum) 
  
  
  incProgress(0.2)
  assocs_df <- select(assocs_df,-association_id)
  
  return (assocs_df)
}
# Reorganise and rename columns
make_pretty <- function(dframe,varnums){
  dframe <- dframe %>%
    rename(Dataset = dataset_label, Effect_type = effect_type, Effect_CIL95 = effect_l95, Effect_CIU95 = effect_u95,
           Effect = effect, N = n, P = p, P_FDR = p_fdr)
  
  # The default columns should be the first columns of the data frame in this order
  if(any(varnums == 2)){
    first.cols <- c("Dataset", "Effect_type", "Variable1", "Variable2", "Effect_CIL95", "Effect_CIU95", "Effect", "N",
                    "P", "P_FDR", "Description1", "Description2")
  }
  else{
    first.cols <- c("Dataset", "Effect_type", "Variable1", "Effect_CIL95", "Effect_CIU95", "Effect", "N",
                    "P", "P_FDR", "Description1")
  }
  # The rest of the columns in alphabetical order
  last.cols <- sort(setdiff(colnames(dframe),first.cols))
  # Reorganise columns
  dframe <- dframe[,c(first.cols,last.cols)]
  
  dframe
}

# Filter a data frame by keywords on columns
# keywords that start with a '-' are exclusions from the search
# keywords that end with a '*' are wildcards
filter_by_keyword <- function(dframe, cols, keywords){
  
  # Split at ',' and remove leading and trailing whitespace
  keywords <- keywords  %>% strsplit(split=",") %>% unlist() %>% trimws()
  
  # Separate exclusions and iclusions
  inclusions <- keywords[!grepl("^-",keywords)]
  exclusions <- keywords[grepl("^-",keywords)] %>% gsub("^-","",.)
  
  if(length(inclusions)){
    # Limit associations to those matching inlcusions
    # First find all the values matching wildcards
    wildcards <- inclusions[grepl("\\*$",inclusions)]
    dframe_filtered <- dframe[1,][-1,] # empty data frame with same colnames as dframe
    if(length(wildcards)){
      for(wc in wildcards){
        wc <- paste("^",gsub("\\*",".\\*",wc),sep="")
        dframe_tmp <- dframe %>% filter_at(.vars = cols, any_vars(grepl(wc,.)))
        dframe_filtered <- union(dframe_filtered,dframe_tmp)
      }
    }
    # Then add non-wildcard variables
    inclusions <- inclusions[!grepl("\\*$",inclusions)]
    if(length(inclusions)){
      dframe_tmp <- dframe %>% filter_at(.vars = cols, any_vars(. %in% inclusions))
      dframe_filtered <- union(dframe_filtered, dframe_tmp)
    }
    dframe <- dframe_filtered
  }
  
  # Exclude by keywords marked with '-'
  if(length(exclusions)){
    # Exclude variables marked with '*' wildcard
    wildcards <- exclusions[grepl("\\*$",exclusions)]
    for(wc in wildcards){
      wc <- paste("^",gsub("\\*",".\\*",wc),sep="")
      # Remove all rows where any of the cols matches wildcard
      dframe <- dframe %>% filter_at(.vars = cols, all_vars(!grepl(wc,.)))
    }
    # Exclude non-wildcard variables
    exclusions <- exclusions[!grepl("\\*$",exclusions)]
    # Remove all rows where any of the cols matches any of the exclusions
    dframe <- dframe %>% filter_at(.vars = cols, all_vars(! . %in% exclusions))
  }
  
  dframe
}

# Filter variables by p-value, keep all variables that
# have at least one association meeting criterion
varfilter_p <- function(dframe,p_limit,varnum,fdr = FALSE){
  if (fdr){
    dframe_fltrd <- dframe %>% filter(P_FDR < p_limit)
  }
  else{
    dframe_fltrd <- dframe %>% filter(P < p_limit)
  }
  if(varnum == 2){
    vars_accepted <- c(dframe_fltrd$Variable1,dframe_fltrd$Variable2) %>% unique()
    dframe <- dframe %>% filter(Variable1 %in% vars_accepted | Variable2 %in% vars_accepted)
  }
  else{
    vars_accepted <- unique(dframe_fltrd$Variable1)
    dframe <- dframe %>% filter(Variable1 %in% vars_accepted)
  }
  
  dframe
}

# Filter variables by effect, keep all variables that
# have at least one association meeting criterion
varfilter_eff <- function(dframe,eff_min = -Inf,eff_max = Inf,varnum){
  dframe_fltrd <- dframe %>% filter(Effect > eff_min & Effect < eff_max)
  if (varnum == 2){
    vars_accepted <- c(dframe_fltrd$Variable1,dframe_fltrd$Variable2) %>% unique()
    dframe <- dframe %>% filter(Variable1 %in% vars_accepted | Variable2 %in% vars_accepted)
  }
  else{
    vars_accepted <- unique(dframe_fltrd$Variable1)
    dframe <- dframe %>% filter(Variable1 %in% vars_accepted)
  }
  
  dframe
}
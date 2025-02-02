library(shiny)
library(DT)
library(DBI)
library(dplyr)
library(tidyr)
library(RPostgreSQL)
library(pool)
library(ggplot2)
library(plotly)

source("visualizations.R")
source("queries.R")

db_info <- read_db_info("../src/database_import.config")

if(!exists("pool")){
  pool <- dbPool(
    drv = RPostgreSQL::PostgreSQL(),
    dbname = db_info$db_name,
    host = db_info$db_host,
    port = db_info$db_port,
    user = db_info$db_user,
    password = db_info$db_password
    #maxSize = 10,
    #idleTimeout = 40000
  )
}

ds_dframe <- get_datasets(pool)
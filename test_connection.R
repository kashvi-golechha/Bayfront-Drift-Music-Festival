library(DBI)
library(RPostgres)

con <- dbConnect(
  RPostgres::Postgres(),
  host = Sys.getenv("MUSICFEST_DB_HOST"),
  port = as.integer(Sys.getenv("MUSICFEST_DB_PORT")),
  dbname = Sys.getenv("MUSICFEST_DB_NAME"),
  user = Sys.getenv("MUSICFEST_DB_USER"),
  password = Sys.getenv("MUSICFEST_DB_PASSWORD"),
  sslmode = "require"
)

print(dbListTables(con))

dbDisconnect(con)
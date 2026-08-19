# Bayfront Planner

A data-driven, interactive festival planning app built with R Shiny and PostgreSQL.

## Overview

Bayfront Planner helps festival-goers plan a personalized three-day music festival weekend 
in San Diego (Aug 21–23, 2026). Users pick their festival pass, browse 327 lodging options, 
choose restaurants and free-time activities, and get a complete day-by-day itinerary with 
budget breakdown and travel recommendations — all powered by live SQL queries against a 
shared PostgreSQL database.

## What We Built

My team and I designed and shipped a full-stack data application end-to-end:

- Designed a fully normalized (3NF) relational database schema across 5 domains before 
  any data was loaded
- Sourced, cleaned, and loaded real data from Yelp, Airbnb, Spotify, and the City of 
  San Diego across 5 independent domains
- Built an ETL pipeline in Python and SQL to clean, standardize, and load 400+ records 
  into a shared PostgreSQL database
- Connected the database live to an R Shiny app using parameterized SQL queries
- Designed a personalized passport badge system and day-by-day budget itinerary generator

## Tech Stack

- **Database:** PostgreSQL (hosted on DigitalOcean)
- **App:** R Shiny
- **Languages:** SQL, R, Python (ETL)
- **Tools:** DBeaver, Git

## Data Sources

| Domain | Source | Rows |
|--------|--------|------|
| Accommodations | Yelp API + Kaggle Airbnb | 327 |
| Performances | Custom-built, Spotify-enriched | 30 |
| Restaurants | Yelp, 14 cuisine types | 50 |
| Free-Time Activities | City of San Diego + official sources | 16 |
| Transportation | MTS GTFS live feed | 105+ routes |

## Database Schema

The database is fully normalized with 17 tables across 8 domains. Domain tables feed a 
shared attendee layer through dedicated bridge tables, no repeated groups, no partial 
dependencies.

## App Features

- **Plan Weekend** — Choose festival pass, lodging, artists, food, and activities
- **My Passport** — Personalized badge system generated from your selections
- **My Plan** — Complete budget breakdown and day-by-day itinerary with transportation 
  recommendations

## Team

Columbia University — Relational Databases & SQL for Analytics

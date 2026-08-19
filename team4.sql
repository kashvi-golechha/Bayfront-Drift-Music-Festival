-- ============================================================
-- team4.sql
-- Bayfront Planner — Relational Database & ETL
-- Columbia University | Applied Analytics | SQL for Analytics
-- Team 4: Kashvi, Zahide, Xiaobei, Adel, Kaisheng, Ming
-- ============================================================
-- This file contains:
--   1. Schema creation (3NF normalized tables)
--   2. Lookup table inserts (festival_days, stages, ticket_options)
--   3. Domain data loads (accommodations, performances, restaurants)

-- ============================================================

-- ============================================================
-- SECTION 1: SCHEMA CREATION (3NF)
-- ============================================================
-- All tables were designed in 3NF before any data was loaded.
-- Domain tables feed a shared attendee layer through bridge tables.
-- No repeated groups, no partial dependencies, no transitive deps.
-- ============================================================

-- ── Shared lookup tables ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS festival_days (
    day_id      int PRIMARY KEY,
    day_name    varchar(10),
    day_date    date
);

CREATE TABLE IF NOT EXISTS stages (
    stage_id    int PRIMARY KEY,
    stage_name  varchar(50),
    genre_focus varchar(50)
);

CREATE TABLE IF NOT EXISTS ticket_options (
    ticket_id       int PRIMARY KEY,
    ticket_type     varchar(10),   -- 'GA' or 'VIP'
    days_covered    int,
    day_label       varchar(20),
    price           numeric(8,2),
    description     varchar(200)
);

-- ── Domain tables ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS accommodations (
    lodging_id              int PRIMARY KEY,
    source                  varchar(20),
    name                    varchar(200),
    property_type           varchar(50),
    address                 varchar(300),
    latitude                numeric(15,10),
    longitude               numeric(15,10),
    rating_5                numeric(3,1),
    price_tier              varchar(5),
    num_reviews             int,
    distance_from_venue_km  numeric(6,2),
    price_per_night         int
);

CREATE TABLE IF NOT EXISTS performances (
    performance_id      int PRIMARY KEY,
    artist_name         varchar(100),
    genre               varchar(50),
    day_id              int REFERENCES festival_days(day_id),
    stage_id            int REFERENCES stages(stage_id),
    start_time          varchar(10),
    end_time            varchar(10),
    origin_country      varchar(50),
    spotify_popularity  int,
    est_fee             int
);

CREATE TABLE IF NOT EXISTS restaurants (
    restaurant_id           int PRIMARY KEY,
    restaurant_name         varchar(100),
    cuisine_type            varchar(50),
    rating                  numeric(3,1),
    review_count            int,
    price_tier              varchar(5),
    area                    varchar(50),
    address                 varchar(200),
    distance_from_venue_km  numeric(6,2),
    latitude                numeric(15,10),
    longitude               numeric(15,10),
    source                  varchar(50),
    price_per_meal          int
);
-- ── Transportation tables ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS transport_routes (
    route_id          varchar(20) PRIMARY KEY,
    agency_id         varchar(20),
    route_short_name  varchar(20),
    route_long_name   varchar(255),
    route_type        integer,
    route_url         text,
    route_color       varchar(20),
    route_text_color  varchar(20),
    route_group       varchar(100),
    route_pattern1    varchar(50),
    route_pattern2    varchar(50)
);

CREATE TABLE IF NOT EXISTS transport_stops (
    stop_id              varchar(50) PRIMARY KEY,
    stop_code            varchar(50),
    stop_name            varchar(50),
    stop_lat             real,
    stop_lon             real,
    zone_id              varchar(50),
    stop_url             varchar(50),
    location_type        integer,
    parent_station       varchar(50),
    wheelchair_boarding  integer,
    intersection_code    varchar(50),
    reference_place      varchar(50),
    stop_name_short      varchar(50),
    stop_place           varchar(50)
);

CREATE TABLE IF NOT EXISTS transport_trips (
    route_id             varchar(50),
    service_id           varchar(50),
    trip_id              integer,
    trip_headsign        varchar(50),
    direction_id         integer,
    block_id             varchar(50),
    shape_id             varchar(50),
    wheelchair_accessible integer,
    bikes_allowed        integer,
    direction_name       varchar(50),
    trip_bikes_allowed   integer,
    trip_headsign_short  varchar(50)
);

CREATE TABLE IF NOT EXISTS stop_times (
    trip_id              integer,
    arrival_time         varchar(50),
    departure_time       varchar(50),
    stop_id              integer,
    stop_sequence        integer,
    stop_headsign        varchar(50),
    pickup_type          integer,
    drop_off_type        integer,
    shape_dist_traveled  real,
    timepoint            integer
);

CREATE TABLE IF NOT EXISTS accommodation_transit_estimates (
    estimate_id              integer PRIMARY KEY,
    lodging_id               integer REFERENCES accommodations(lodging_id),
    day_id                   integer REFERENCES festival_days(day_id),
    departure_time           varchar(10),
    mode                     varchar(20),
    estimated_minutes        numeric(5,1),
    num_stops                integer,
    origin_stop              varchar(10) REFERENCES transport_stops(stop_id),
    destination_stop         varchar(10) REFERENCES transport_stops(stop_id),
    trip_id                  varchar(20),
    name                     varchar(64),
    property_type            varchar(50),
    address                  varchar(50),
    price_tier               varchar(50),
    distance_from_venue_km   real,
    day                      varchar(50)
);
-- ── Attendee + check-in tables (Creative Feature) ──────

CREATE TABLE IF NOT EXISTS attendees (
    attendee_id         int PRIMARY KEY,
    attendee_name       varchar(50),
    total_budget        numeric(8,2),
    chosen_lodging_id   int REFERENCES accommodations(lodging_id)
);

CREATE TABLE IF NOT EXISTS performance_checkins (
    checkin_id      int PRIMARY KEY,
    attendee_id     int REFERENCES attendees(attendee_id),
    performance_id  int REFERENCES performances(performance_id),
    checkin_time    timestamp
);

CREATE TABLE IF NOT EXISTS restaurant_checkins (
    checkin_id      int PRIMARY KEY,
    attendee_id     int REFERENCES attendees(attendee_id),
    restaurant_id   int REFERENCES restaurants(restaurant_id),
    checkin_time    timestamp
);

CREATE TABLE IF NOT EXISTS activity_checkins (
    checkin_id      int PRIMARY KEY,
    attendee_id     int REFERENCES attendees(attendee_id),
    activity_id     int REFERENCES free_time_activities(activity_id),
    checkin_time    timestamp
);

-- ============================================================
-- SECTION 2: LOOKUP TABLE INSERTS
-- ============================================================
-- festival_days: 3 days of the festival (Aug 21-23, 2026)
-- stages: 3 stages by genre focus
-- ticket_options: 6 pass options (GA/VIP x 1/2/3 day)
-- ============================================================

INSERT INTO festival_days (day_id, day_name, day_date) VALUES
(1, 'Friday',   '2026-08-21'),
(2, 'Saturday', '2026-08-22'),
(3, 'Sunday',   '2026-08-23');

INSERT INTO stages (stage_id, stage_name, genre_focus) VALUES
(1, 'Bahia Stage',   'Tech House / Techno'),
(2, 'Pacific Stage', 'Afro House / Ethnic World'),
(3, 'Gaslamp Stage', 'Indie Dance / Indie Ethnic');

INSERT INTO ticket_options (ticket_id, ticket_type, days_covered, day_label, price, description) VALUES
(1, 'GA',  1, '1-Day',   89.00,  'General admission for one day of your choice. Access to all stages and general festival grounds.'),
(2, 'GA',  2, '2-Day',  159.00,  'General admission for any two days. Access to all stages and general festival grounds.'),
(3, 'GA',  3, '3-Day',  219.00,  'Full festival general admission. Access to all stages and general festival grounds for all three days.'),
(4, 'VIP', 1, '1-Day',  189.00,  'VIP access for one day. Includes VIP lounge, priority entry, dedicated bars, and exclusive viewing areas.'),
(5, 'VIP', 2, '2-Day',  329.00,  'VIP access for any two days. Includes VIP lounge, priority entry, dedicated bars, and exclusive viewing areas.'),
(6, 'VIP', 3, '3-Day',  449.00,  'Full festival VIP access. Includes VIP lounge, priority entry, dedicated bars, exclusive viewing areas, and festival merch.');

-- ============================================================
-- SECTION 3: ACCOMMODATIONS (327 rows)
-- ============================================================
-- Source: Yelp API + Kaggle Airbnb dataset
-- price_per_night simulated using tier buckets:
--   $   = $55-95/night   (hostels, budget hotels)
--   $$  = $105-195/night (mid-range hotels, serviced apartments)
--   $$$  = $210-380/night (upscale hotels, resorts)
-- NaN price_tier rows (all Hotels) assigned $$ by property type
-- ============================================================

INSERT INTO accommodations (lodging_id, source, name, property_type, address,
    latitude, longitude, rating_5, price_tier, num_reviews,
    distance_from_venue_km, price_per_night) VALUES
(1, 'Yelp', 'Le Meridien', 'Hotel', '501 W A St, San Diego, CA 92101', 32.718714667257295, -117.16774300383524, 0.0, '$$', 0, 0.16, 186),
(2, 'Yelp', 'Hotel Republic San Diego', 'Hotel', '421 West B Street, San Diego, CA 92101', 32.7175333267482, -117.166840233135, 3.5, '$$', 354, 0.16, 119),
(3, 'Yelp', 'The Guild Hotel', 'Hotel', '500 West Broadway, San Diego, CA 92101', 32.715919, -117.167855, 3.9, '$$', 259, 0.19, 108),
(4, 'Yelp', 'The Westin San Diego', 'Hotel', '400 W Broadway, San Diego, CA 92101', 32.71625, -117.16693, 3.2, '$$$', 694, 0.21, 280),
(5, 'Yelp', 'The Westin San Diego Bayview', 'Hotel', '1051 Columbia St, San Diego, CA 92101', 32.716155, -117.166853, 3.3, '$$', 66, 0.22, 136),
(6, 'Yelp', 'Kasa Little', 'Hotel', '1331 Columbia St, San Diego, CA 92101', 32.71930276194508, -117.16719495180348, 0.0, '$$', 0, 0.24, 133),
(7, 'Yelp', 'Best Western Plus Bayside Inn', 'Hotel', '555 W Ash St, San Diego, CA 92101', 32.719517, -117.167631, 3.7, '$$', 149, 0.24, 122),
(8, 'Yelp', 'Tic Hotels', 'Hotel', '555 W Ash St, San Diego, CA 92101', 32.71961, -117.16783, 0.0, '$$', 0, 0.25, 118),
(9, 'Yelp', 'Residence Inn by Marriott San Diego Downtown/Bayfront', 'Hotel', '900 Bayfront Ct, San Diego, CA 92101', 32.7169661344727, -117.171276215344, 3.9, '$$', 137, 0.26, 191),
(10, 'Yelp', 'InterContinental San Diego', 'Hotel', '901 Bayfront Ct, San Diego, CA 92101', 32.71674170630989, -117.17138737423883, 3.4, '$$$', 343, 0.27, 349),
(11, 'Yelp', 'Carte Hotel San Diego Downtown, Curio Collection by Hilton', 'Hotel', '401 W Ash St, San Diego, CA 92101', 32.7197260648, -117.16677040738062, 3.6, '$$', 309, 0.3, 116),
(12, 'Yelp', 'Carte Hotel', 'Hotel', '401 W Ash St, San Diego, CA 92101', 32.7198257286736, -117.16662757350582, 0.0, '$$', 0, 0.32, 180),
(13, 'Yelp', 'SpringHill Suites by Marriott San Diego Downtown/Bayfront', 'Hotel', '900 Bayfront Ct, San Diego, CA 92101', 32.7167631, -117.1720121, 3.9, '$$', 277, 0.33, 159),
(14, 'Airbnb', 'The Bunk House Downtown', 'Hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71928, -117.17163, NULL, '$$', 0, 0.35, 109),
(15, 'Yelp', 'The Sofia Hotel', 'Hotel', '150 W Broadway, San Diego, CA 92101', 32.7162259184028, -117.164393663406, 3.7, '$$', 1009, 0.42, 108),
(16, 'Yelp', 'Wyndham San Diego Bayside', 'Hotel', '1355 N Hbr Dr, San Diego, CA 92101', 32.71918496804681, -117.17258349999923, 2.6, '$$', 937, 0.42, 116),
(17, 'Yelp', 'Hampton Inn San Diego-Downtown', 'Hotel', '1531 Pacific Hwy, San Diego, CA 92101', 32.7212093191854, -117.170555591585, 3.0, '$$', 420, 0.45, 132),
(18, 'Yelp', 'Carlsbad by the Sea Hotel', 'Hotel', '1059 1st Ave, San Diego, CA 92101', 32.7162779867649, -117.163762003183, 0.0, '$$', 0, 0.47, 134),
(19, 'Yelp', 'Mission Bay Shores Hotel', 'Hotel', '1059 1st Ave, San Diego, CA 92101', 32.7162779867649, -117.163762003183, 2.0, '$$', 1, 0.47, 169),
(20, 'Yelp', 'The Bristol Hotel - San Diego', 'Hotel', '1055 1st Ave, San Diego, CA 92101', 32.71643, -117.16351, 3.5, '$$', 528, 0.49, 182),
(21, 'Airbnb', 'The Local Hostel San Diego', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72158, -117.16583, 4.0, '$$', 8, 0.52, 108),
(22, 'Yelp', 'Reiss Hotel', 'Hotel', '1432 1st Ave, San Diego, CA 92101', 32.7202476561069, -117.163926288486, 3.7, '$$', 10, 0.53, 176),
(23, 'Airbnb', 'Little Italy Hostel', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72191, -117.1659, 4.7, '$', 84, 0.55, 67),
(24, 'Yelp', 'The Westgate Hotel', 'Hotel', '1055 2nd Ave, San Diego, CA 92101', 32.71631, -117.16249, 3.4, '$$$', 169, 0.59, 376),
(25, 'Yelp', 'Urban Boutique Hotel', 'Hotel', '1654 Columbia St, San Diego, CA 92101', 32.7226959501406, -117.167549300594, 3.4, '$$', 392, 0.59, 194),
(26, 'Yelp', 'The Westgate Hotel', 'Hotel', '1055 2nd Ave, San Diego, CA 92101', 32.71631, -117.16249, 3.7, '$$$', 720, 0.59, 349),
(27, 'Yelp', 'The Westin San Diego Gaslamp Quarter', 'Hotel', '910 Broadway Circle, San Diego, CA 92101', 32.71446, -117.16333, 3.5, '$$$', 747, 0.6, 317),
(28, 'Airbnb', 'Urban Farmhouse Hostel', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72249, -117.16554, 4.5, '$', 31, 0.62, 69),
(29, 'Airbnb', 'Downtown Queen Hostel', 'Hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72252, -117.16564, 4.8, '$', 24, 0.62, 83),
(30, 'Yelp', 'La Pensione Hotel', 'Hotel', '606 W Date St, San Diego, CA 92101', 32.72323, -117.1686, 3.2, '$$', 297, 0.64, 180),
(31, 'Airbnb', 'Gaslamp Quarter Inn', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72295, -117.16638, 5.0, '$$', 2, 0.64, 140),
(32, 'Yelp', 'Embassy Suites by Hilton San Diego Bay Downtown', 'Hotel', '601 Pacific Hwy, San Diego, CA 92101', 32.71195501641301, -117.1705880910281, 3.1, '$$$', 712, 0.64, 211),
(33, 'Yelp', 'Courtyard By Marriott', 'Hotel', '1646 Front St, San Diego, CA 92101', 32.7224813, -117.16487747423656, 3.7, '$$', 21, 0.65, 125),
(34, 'Yelp', 'Hotel Hennes', 'Hotel', 'San Diego, CA', 32.715690612793, -117.161720275879, 0.0, '$$', 0, 0.67, 194),
(35, 'Yelp', 'The Icon Hotel San Diego', 'Hotel', '225 W Date St, San Diego, CA 92101', 32.7228251, -117.1653354, 0.0, '$$', 0, 0.67, 159),
(36, 'Airbnb', 'Balcony Loft Downtown', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72303, -117.16565, 4.35, '$', 6, 0.67, 76),
(37, 'Yelp', 'Motel 6', 'Hotel', '1546 2nd Ave, San Diego, CA 92101', 32.7214622, -117.1631650098277, 2.6, '$', 271, 0.67, 72),
(38, 'Yelp', 'The Strand Hotel', 'Hotel', '225 W Date St, San Diego, CA 92101', 32.7228251, -117.1653354, 0.0, '$$', 0, 0.67, 124),
(39, 'Yelp', 'Little Italy Inn', 'Hotel', '1736 State St, San Diego, CA 92101', 32.72340136314832, -117.166869007051, 4.0, '$$', 2, 0.68, 132),
(40, 'Yelp', 'Residence Inn by Marriott San Diego Downtown', 'Hotel', '1747 Pacific Hwy, San Diego, CA 92101', 32.7233793621167, -117.170670032501, 3.5, '$$', 141, 0.68, 148),
(41, 'Airbnb', 'Pacific Backpackers Hostel', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.7232, -117.16599, 4.8, '$', 43, 0.68, 61),
(42, 'Yelp', 'The US Grant, a Luxury Collection Hotel, San Diego', 'Hotel', '326 Broadway, San Diego, CA 92101', 32.71607, -117.16153, 4.0, '$$$', 1061, 0.68, 233),
(43, 'Airbnb', 'Harbor View Hostel', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72314, -117.16545, 4.75, '$', 62, 0.69, 79),
(44, 'Yelp', 'Wilsonian Hotel', 'Hotel', '1545 Second Ave, San Diego, CA 92101', 32.72153813814587, -117.16265, 0.0, '$$', 0, 0.72, 117),
(45, 'Yelp', 'The Dextro', 'Hotel', '1617 1st Ave, San Diego, CA 92101', 32.72233576948759, -117.16341134480044, 2.7, '$$', 469, 0.72, 150),
(46, 'Yelp', 'Harborside Hotel San Diego', 'Hotel', '645 Front St, San Diego, CA 92101', 32.7119445800781, -117.164505004883, 0.0, '$$', 0, 0.73, 149),
(47, 'Airbnb', 'San Diego Vista RG93', 'Hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72391, -117.16636, NULL, '$$$', 0, 0.74, 364),
(48, 'Airbnb', 'The Cozy Room Downtown', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72375, -117.16584, 4.5, '$', 34, 0.74, 71),
(49, 'Yelp', 'Centre City', 'Hotel', '1450 4th Ave, San Diego, CA 92101', 32.72054, -117.16141, 4.0, '$$', 1, 0.75, 110),
(50, 'Airbnb', 'The Social Hostel', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.7239, -117.16615, 4.7, '$', 103, 0.75, 84),
(51, 'Yelp', 'Days Inn San Diego Airport Convention Center/Harbor View', 'Hotel', '1919 Pacific Hwy, San Diego, CA 92101', 32.7240899, -117.17093, 2.4, '$$', 35, 0.76, 173),
(52, 'Airbnb', 'Gaslamp Plaza Mini Suite', 'Hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71552, -117.16077, 5.0, '$$', 1, 0.76, 120),
(53, 'Airbnb', 'The Bungalow House', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72374, -117.16528, 4.2, '$$$', 16, 0.76, 306),
(54, 'Airbnb', 'Gaslamp District Flats', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71523, -117.16094, 4.65, '$$', 4, 0.76, 115),
(55, 'Airbnb', 'The Quad Hostel', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72386, -117.16536, 4.65, '$', 21, 0.77, 90),
(56, 'Yelp', 'Manchester Grand Hyatt San Diego', 'Hotel', '1 Market Pl, San Diego, CA 92101', 32.71058, -117.16808, 3.6, '$$$', 1970, 0.77, 285),
(57, 'Yelp', 'Super 8 Motel', 'Hotel', '1835 Columbia St, San Diego, CA 92101', 32.7243919372559, -117.167259216309, 1.6, '$$', 5, 0.78, 185),
(58, 'Airbnb', 'Wyndham Gaslamp Studio', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71543, -117.16064, 4.9, '$$', 8, 0.78, 184),
(59, 'Airbnb', 'Gaslamp Grand Apartments', 'Hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71445, -117.16097, 5.0, '$$$', 3, 0.79, 302),
(60, 'Airbnb', 'Gaslamp Plaza Suites', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71559, -117.16049, 5.0, '$$$', 1, 0.79, 357),
(61, 'Airbnb', 'Comic-Con Deluxe Studio', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71551, -117.16052, NULL, '$$$', 0, 0.79, 259),
(62, 'Airbnb', 'Gaslamp Boutique Flats', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71461, -117.16093, NULL, '$$', 0, 0.79, 195),
(63, 'Yelp', 'Porto Vista Hotel', 'Hotel', '1835 Columbia St, San Diego, CA 92101', 32.724506230173084, -117.16754947423532, 2.3, '$$', 1240, 0.79, 113),
(64, 'Yelp', 'Granger Hotel Gaslamp Quarter', 'Hotel', '964 Fifth Ave, San Diego, CA 92101', 32.71541982446156, -117.16046625569676, 4.0, '$$', 54, 0.8, 110),
(65, 'Airbnb', 'The Top Rated Hostel Dorm', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72392, -117.16484, 4.7, '$', 68, 0.8, 69),
(66, 'Yelp', 'Beechwood Hotel', 'Hotel', '1465 4th Ave, San Diego, CA 92101', 32.720784, -117.160854, 2.3, '$$$', 3, 0.81, 284),
(67, 'Airbnb', 'Studio Suite Romantic Getaway Gaslamp District', 'Aparthotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71536, -117.16033, NULL, '$$', 1, 0.81, 115),
(68, 'Airbnb', 'New Year''s Eve in Gaslamp Quarter and more!', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71458, -117.16052, NULL, '$$', 0, 0.82, 134),
(69, 'Airbnb', 'Gaslamp Plaza Suites 2', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71543, -117.16017, NULL, '$$', 0, 0.82, 117),
(70, 'Airbnb', 'San Diego Studio at Wyndham Harbour Lights', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71549, -117.16016, NULL, '$$$', 0, 0.82, 307),
(71, 'Airbnb', 'Downtown Hostel Female Dorm', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71182, -117.16304, 4.35, '$', 11, 0.82, 72),
(72, 'Yelp', 'The Sandford Hotel', 'Hotel', '1301 5th Ave Ofc, San Diego, CA 92101', 32.71917, -117.1599, 1.0, '$$', 1, 0.83, 163),
(73, 'Airbnb', 'Comic-Con San Diego Gaslamp Plaza 1 BDR Suite 4pl', 'Aparthotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.7145, -117.16031, 4.65, '$$$', 3, 0.84, 372),
(74, 'Yelp', 'Alma San Diego Downtown, a Tribute Portfolio Hotel', 'Hotel', '1047 Fifth Ave, San Diego, CA 92101', 32.71632, -117.15974, 3.2, '$$', 48, 0.84, 151),
(75, 'Airbnb', 'Gaslamp European-Style Boutique - Suite', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71428, -117.16043, 5.0, '$$', 1, 0.84, 125),
(76, 'Airbnb', 'Cozy & roomy apartment right at downtown San Diego', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71454, -117.16028, 5.0, '$', 1, 0.85, 78),
(77, 'Airbnb', 'Gaslamp Quarter Resort 1 BR Condo', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71387, -117.16065, 5.0, '$$', 2, 0.85, 150),
(78, 'Airbnb', 'Gaslamp pad', 'Aparthotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71404, -117.16051, NULL, '$$$', 0, 0.85, 263),
(79, 'Airbnb', 'Gaslamp District Apartments', 'Serviced apartment', 'CA, United States, CA, 92101', 32.71225, -117.16194, 4.75, '$$', 11, 0.85, 190),
(80, 'Airbnb', 'Gaslamp Studio close to Convention Center', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71431, -117.16032, 5.0, '$$', 2, 0.85, 139),
(81, 'Airbnb', 'Gaslamp Plaza Suite', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71387, -117.16063, NULL, '$$', 1, 0.85, 194),
(82, 'Airbnb', 'Gaslamp 1 BR Suite - Walk to Comic Con', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71444, -117.16017, NULL, '$$$', 0, 0.86, 375),
(83, 'Airbnb', 'Gaslamp District 5th Ave Apt', 'Serviced apartment', 'CA, United States, CA, 92101', 32.71112, -117.1634, 4.65, '$$', 3, 0.86, 114),
(84, 'Airbnb', 'Wyndham Harbour Lights in Vibrant Gaslamp Quarter', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71421, -117.16031, 5.0, '$$$', 1, 0.86, 365),
(85, 'Yelp', 'Paris Inn San Diego', 'Hotel', '759 4th Ave, San Diego, CA 92101', 32.7131599187851, -117.161000669003, 0.0, '$$', 0, 0.86, 186),
(86, 'Airbnb', 'Downtown Hostel Female Dorm 3', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71209, -117.16189, 5.0, '$', 1, 0.87, 65),
(87, 'Airbnb', 'Heart of Gaslamp', 'Aparthotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71423, -117.16012, 5.0, '$$$', 3, 0.87, 346),
(88, 'Airbnb', 'Downtown Hostel Mixed Dorm', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71176, -117.16223, 3.0, '$', 2, 0.87, 70),
(89, 'Airbnb', 'Harbour Lights Studio San Diego', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71405, -117.16028, NULL, '$$$', 0, 0.87, 251),
(90, 'Yelp', 'Gaslamp Plaza Suites', 'Hotel', '520 E St, San Diego, CA 92101', 32.71488653395858, -117.1597607, 3.6, '$$', 299, 0.88, 164),
(91, 'Yelp', 'The Keating Hotel', 'Hotel', '432 F St, San Diego, CA 92101', 32.7137560296064, -117.1603292057614, 3.5, '$$', 10, 0.88, 153),
(92, 'Airbnb', 'Studio Wyndham Harbor Lights, San Diego CA', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71412, -117.16014, 5.0, '$$$', 1, 0.88, 279),
(93, 'Airbnb', 'San Diego Gaslamp Quarter - Deluxe Studio Suite', 'Hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71546, -117.15948, NULL, '$$$', 0, 0.88, 373),
(94, 'Airbnb', 'Gaslamp San Diego Studio', 'Hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71372, -117.16038, 5.0, '$$', 1, 0.88, 193),
(95, 'Airbnb', 'Downtown Mixed Dorm Hostel', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71382, -117.16017, NULL, '$$', 0, 0.89, 176),
(96, 'Airbnb', 'Lucky Ds Hostel', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71476, -117.15953, 4.6, '$$', 5, 0.9, 133),
(97, 'Airbnb', 'WorldMark San Diego', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71241, -117.16108, 3.5, '$', 2, 0.9, 75),
(98, 'Airbnb', 'Blissful Bayside Apartments', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71533, -117.15929, NULL, '$$', 0, 0.9, 112),
(99, 'Airbnb', 'Hawthorne Historic Inn', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71453, -117.15965, NULL, '$$$', 0, 0.9, 268),
(100, 'Airbnb', 'The Female Dorm Hostel', 'Aparthotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71448, -117.15955, NULL, '$$$', 0, 0.91, 218),
(101, 'Airbnb', 'Marriott Comic-Con Studio', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.7111, -117.1623, 4.0, '$', 1, 0.92, 75),
(102, 'Airbnb', 'Marriott Pulse San Diego', 'Hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71446, -117.15943, 4.25, '$$', 5, 0.92, 156),
(103, 'Airbnb', 'Porto Vista Hotel', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71448, -117.15949, NULL, '$$', 0, 0.92, 139),
(104, 'Airbnb', 'Great Location San Diego Suites', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71856, -117.15882, NULL, '$$$', 0, 0.92, 226),
(105, 'Airbnb', 'Hotel Marriott Vacation Club', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71205, -117.16114, 4.4, '$', 23, 0.92, 68),
(106, 'Airbnb', 'The Spacious Guest Suite', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71398, -117.15961, NULL, '$$', 0, 0.93, 177),
(107, 'Airbnb', 'Marriott Vacation Club Pulse', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71439, -117.15938, NULL, '$$', 0, 0.93, 145),
(108, 'Airbnb', 'Walk to ComicCon Suite Hotel', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71434, -117.15939, NULL, '$$$', 0, 0.93, 264),
(109, 'Airbnb', 'Hawthorne Inn Room 106', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71388, -117.15952, NULL, '$$', 0, 0.94, 188),
(110, 'Airbnb', 'Extraordinary High Rise Apartments', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71049, -117.16301, 4.35, '$', 3, 0.94, 86),
(111, 'Airbnb', 'The Private Room Downtown', 'Hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71761, -117.15859, NULL, '$$$', 0, 0.94, 311),
(112, 'Airbnb', 'The Downtown Studio San Diego', 'Serviced apartment', 'CA, United States, CA, 92101', 32.71128, -117.16163, 4.8, '$$', 41, 0.95, 187),
(113, 'Airbnb', 'Hawthorne Inn Room 101', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71939, -117.15867, NULL, '$$$', 0, 0.95, 327),
(114, 'Airbnb', 'Gorgeous Apartment Downtown', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71049, -117.16277, NULL, '$', 0, 0.95, 64),
(115, 'Airbnb', 'Big Studio with Ocean View', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71037, -117.16286, 3.0, '$', 3, 0.96, 71),
(116, 'Airbnb', 'Mixed Dorm Hostel Downtown', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71966, -117.1585, 5.0, '$$', 2, 0.97, 122),
(117, 'Airbnb', 'The Dorm Hostel', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71906, -117.15838, 5.0, '$$$', 18, 0.97, 273),
(118, 'Airbnb', 'Hawthorne Inn Room 109', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71219, -117.1603, 4.4, '$', 26, 0.98, 90),
(119, 'Airbnb', 'Cozy Travelers Paradise', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71028, -117.1625, 3.65, '$', 8, 0.99, 89),
(120, 'Airbnb', 'Classy Modern Studio Downtown', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71098, -117.16131, 5.0, '$', 4, 1.0, 71),
(121, 'Airbnb', 'Hawthorne Inn Room 102', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71152, -117.16058, 4.45, '$', 120, 1.0, 92),
(122, 'Airbnb', 'Special Studio Center San Diego', 'Hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72577, -117.16424, 5.0, '$$$', 1, 1.01, 319),
(123, 'Airbnb', 'Downtown San Diego Parking Suite', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.72531, -117.16265, 4.9, '$$', 34, 1.03, 179),
(124, 'Airbnb', 'Worldmark Balboa Park Studio', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72631, -117.16472, 4.9, '$', 65, 1.04, 80),
(125, 'Airbnb', 'Hawthorne Inn Room 107', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71055, -117.16113, 4.5, '$', 6, 1.04, 78),
(126, 'Airbnb', 'Studio Hotel Balboa Park', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71841, -117.15741, NULL, '$$$', 0, 1.05, 266),
(127, 'Airbnb', 'Cozy Modern Style Downtown', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71794, -117.15735, NULL, '$$$', 0, 1.05, 245),
(128, 'Airbnb', 'Luxurious Balboa Park Studio', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72614, -117.16414, NULL, '$$', 0, 1.05, 170),
(129, 'Airbnb', 'Downtown Female Dorm Hostel', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71984, -117.1576, NULL, '$$$', 0, 1.06, 336),
(130, 'Airbnb', 'The 1 Bed Mixed Dorm', 'Hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71772, -117.15726, 5.0, '$$$', 1, 1.06, 233),
(131, 'Airbnb', 'Hawthorne Inn Room 108', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.72683, -117.1653, 4.8, '$$', 42, 1.08, 111),
(132, 'Airbnb', 'Female Dorm Hostel Downtown', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71767, -117.15706, 5.0, '$$', 3, 1.08, 119),
(133, 'Airbnb', 'Lucky D''s Private Dorm', 'Hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71778, -117.15709, 5.0, '$$$', 1, 1.08, 249),
(134, 'Airbnb', 'Cozy Cute Downtown Paradise', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72714, -117.16456, 4.7, '$', 49, 1.14, 95),
(135, 'Airbnb', 'Classy Splash Modern Studio', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71399, -117.15671, 5.0, '$$$', 1, 1.18, 250),
(136, 'Airbnb', 'Hawthorne Inn Room 103', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71297, -117.15691, 4.5, '$', 50, 1.2, 82),
(137, 'Airbnb', 'Special Studio 5th Avenue', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.72223, -117.15706, 4.95, '$', 34, 1.2, 93),
(138, 'Airbnb', 'Gaslamp District Apt 5th Ave', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72775, -117.16457, 4.9, '$$', 26, 1.2, 113),
(139, 'Airbnb', '41 Gaslamp District Apt', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71036, -117.15889, 5.0, '$$', 1, 1.21, 154),
(140, 'Airbnb', 'Cozy Cute Travelers Downtown', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.7281, -117.1648, 4.95, '$$', 35, 1.23, 153),
(141, 'Airbnb', 'The Hip Hostel Mixed Dorm', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71132, -117.1576, 4.55, '$', 182, 1.24, 93),
(142, 'Airbnb', 'The Hip Hostel Dorm Room', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71113, -117.15778, 4.7, '$', 202, 1.24, 84),
(143, 'Airbnb', 'Hawthorne Historic Inn - Room 109', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72796, -117.1638, 4.9, '$', 72, 1.25, 88),
(144, 'Airbnb', 'Cozy Travelers Paradise Downtown', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.72086, -117.15572, 4.75, '$', 52, 1.26, 71),
(145, 'Airbnb', 'Lucky Ds Hostel Dorm', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71095, -117.15749, 4.55, '$', 165, 1.27, 90),
(146, 'Airbnb', 'Glam Modern Studio Downtown', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.72011, -117.15522, 4.8, '$', 47, 1.28, 55),
(147, 'Airbnb', 'Hawthorne Historic Inn - Room 102', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72837, -117.16407, 4.75, '$', 39, 1.28, 62),
(148, 'Airbnb', 'Special Studio in Center of San Diego', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.7285, -117.16465, 4.85, '$', 71, 1.28, 89),
(149, 'Airbnb', 'Downtown San Diego w. parking', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71541, -117.15492, 4.65, '$', 6, 1.3, 72),
(150, 'Airbnb', 'Worldmark Balboa Park Studio', 'Aparthotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71822, -117.15472, 5.0, '$$$', 1, 1.3, 374),
(151, 'Airbnb', 'Hawthorne Historic Inn - Room 107', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.72803, -117.16248, 4.85, '$', 36, 1.3, 76),
(152, 'Airbnb', 'Studio Hotel Less Desirable Location - Balboa Park', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.7183, -117.15458, 4.0, '$', 1, 1.31, 62),
(153, 'Airbnb', 'COZY & MODERN STYLE @ DOWNTOWN', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.72221, -117.15578, 4.9, '$', 45, 1.31, 73),
(154, 'Airbnb', 'Luxurious Balboa Park Studio Hotel', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71854, -117.15455, 5.0, '$', 1, 1.32, 82),
(155, 'Airbnb', 'Comic Con Hotel-Condo - Walk to Convention Center!', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71891, -117.15459, NULL, '$$$', 0, 1.32, 250),
(156, 'Airbnb', 'Elegant Studio with Kitchenette, Comic-Con 2018', 'Resort', 'San Diego, CA, United States, San Diego, CA 92101', 32.71849, -117.15454, 5.0, '$$$', 1, 1.32, 326),
(157, 'Airbnb', 'Balboa Park Hotel Suite', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71856, -117.15448, 4.5, '$$', 2, 1.33, 105),
(158, 'Airbnb', 'Beautiful High-Rise building with Panoramic Views', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71579, -117.15425, 4.75, '$$$', 74, 1.36, 277),
(159, 'Airbnb', 'Balboa Park 1BR Apartment', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71883, -117.15389, NULL, '$$', 0, 1.38, 169),
(160, 'Airbnb', 'The Hip Hostel Female Dorm', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92101', 32.71074, -117.15629, 4.3, '$', 89, 1.38, 66),
(161, 'Airbnb', 'Studio Hotel Unit @ SanDiego - BP Condo Resort', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71814, -117.15383, 4.6, '$$', 10, 1.38, 169),
(162, 'Airbnb', '8BR Place in the Heart of Downtown San Diego!', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92101', 32.71253, -117.15511, 4.05, '$$$', 20, 1.38, 237),
(163, 'Airbnb', 'Walking distance to Balboa park 1 bedroom Condo', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71819, -117.15372, NULL, '$$', 0, 1.39, 185),
(164, 'Airbnb', 'WMK San Diego Balboa Park-Studio', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71801, -117.15377, 3.0, '$', 1, 1.39, 74),
(165, 'Airbnb', 'Luxurious Balboa Park Condo - 1bed Hotel unit', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71861, -117.15367, 5.0, '$$', 2, 1.4, 186),
(166, 'Airbnb', 'Studio Hotel - Special Needs - Balboa Park', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71894, -117.15367, 5.0, '$', 5, 1.41, 87),
(167, 'Airbnb', 'World Mark Near Gas Lamp', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71819, -117.15334, NULL, '$$$', 0, 1.43, 365),
(168, 'Airbnb', 'Walk to Gaslamp! Private room AMAZING LOCATION', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92101', 32.71247, -117.15428, 4.35, '$$', 13, 1.45, 130),
(169, 'Airbnb', '~Gorgeous 1 Bdrm Unit w/Kitchen and Rooftop Deck~', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71854, -117.15304, NULL, '$$', 0, 1.46, 124),
(170, 'Airbnb', 'Large Clean Bedroom Ideal for Grads, Intern, Coder', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71717, -117.15184, 5.0, '$', 2, 1.57, 78),
(171, 'Airbnb', 'SD Stylish Studio Downtown', 'Aparthotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.70902, -117.15471, 4.5, '$$$', 25, 1.61, 251),
(172, 'Airbnb', 'East Village - Ideal for Student or Intern', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71753, -117.15135, NULL, '$', 0, 1.61, 89),
(173, 'Airbnb', 'Clean Bedroom - Ideal for Student, Intern, Coder', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71683, -117.15142, NULL, '$', 0, 1.61, 88),
(174, 'Airbnb', 'SD Superior Apartel', 'Aparthotel', 'San Diego, CA, United States, San Diego, CA', 32.71053, -117.15328, 4.95, '$$$', 23, 1.63, 210),
(175, 'Airbnb', 'XL. Clean Bedroom / Fun Downtown San Diego', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92101', 32.71743, -117.1512, 5.0, '$', 2, 1.63, 93),
(176, 'Airbnb', 'SD Deluxe Apartel', 'Aparthotel', 'San Diego, CA, United States, San Diego, CA', 32.71097, -117.15286, 4.7, '$$$', 24, 1.64, 292),
(177, 'Airbnb', 'SD Diamond Apartel', 'Aparthotel', 'San Diego, CA, United States, San Diego, CA 92101', 32.70893, -117.15339, 5.0, '$$$', 7, 1.71, 335),
(178, 'Airbnb', 'Large 1 Bedroom Downtown', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92103', 32.73271, -117.17269, 5.0, '$$$', 2, 1.73, 214),
(179, 'Airbnb', 'Cottage - NO VACANCY', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92103', 32.73203, -117.16168, NULL, '$', 0, 1.74, 62),
(180, 'Airbnb', 'SD Platinum Apartel', 'Aparthotel', 'San Diego, CA, United States, San Diego, CA', 32.70998, -117.15217, 4.85, '$$$', 19, 1.75, 302),
(181, 'Airbnb', 'Historic Manor downtown San Diego offers Weddings!', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92103', 32.73217, -117.16165, NULL, '$$$', 0, 1.76, 288),
(182, 'Airbnb', 'The Downtown Apt San Diego', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92102', 32.71521, -117.14496, NULL, '$', 0, 2.23, 70),
(183, 'Airbnb', 'San Diego Suite with Classical interior', 'Resort', 'San Diego, CA, United States, San Diego, CA 92103', 32.73743, -117.1609, NULL, '$$$', 0, 2.33, 224),
(184, 'Airbnb', 'San Diego King Studio at Inn at the Park Resort', 'Resort', 'San Diego, CA, United States, San Diego, CA 92103', 32.73748, -117.16101, NULL, '$$$', 0, 2.33, 271),
(185, 'Airbnb', '2 Bedroom near San Diego Zoo', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92103', 32.73745, -117.16064, NULL, '$$', 0, 2.34, 177),
(186, 'Airbnb', 'Barrio Bed Station- #5 -Walk to Convention Center', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92113', 32.70466, -117.14854, 4.7, '$', 14, 2.36, 60),
(187, 'Airbnb', 'Barrio Bed Station- #3 -Walk to Convention Center', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92113', 32.70433, -117.14864, 5.0, '$', 6, 2.37, 60),
(188, 'Airbnb', 'Bedroom/Suite', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92102', 32.71169, -117.14428, 4.9, '$', 9, 2.37, 86),
(189, 'Airbnb', 'Inn at The Park - Studio King', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92103', 32.73781, -117.16046, NULL, '$$', 0, 2.38, 113),
(190, 'Airbnb', 'WorldMark San Diego - Inn at the Park', 'Resort', 'San Diego, CA, United States, San Diego, CA 92103', 32.73769, -117.16023, NULL, '$', 0, 2.38, 89),
(191, 'Airbnb', 'Barrio Bed Station- #8 -Walk to Convention Center', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92113', 32.7045, -117.14823, 4.85, '$', 21, 2.39, 63),
(192, 'Airbnb', 'Luxurious Inn at the Park Condo - Studio Queen', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92103', 32.738, -117.16053, NULL, '$$', 0, 2.4, 121),
(193, 'Airbnb', 'Little Italy San Diego Apartment', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92103', 32.7381, -117.16057, 4.0, '$$$', 1, 2.41, 378),
(194, 'Airbnb', 'Studio - San Diego, California - Inn at the Park', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92103', 32.73815, -117.16067, NULL, '$$', 0, 2.41, 165),
(195, 'Airbnb', 'Private Boutique Hotel-Walk to the Zoo!', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92103', 32.73812, -117.16047, 1.0, '$$', 1, 2.42, 175),
(196, 'Airbnb', 'INN @ THE PARK-TRENDY LOCATION, HIP BOUTIQUE HOTEL', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92103', 32.73827, -117.15959, NULL, '$$$', 0, 2.46, 252),
(197, 'Airbnb', 'Inn at the Park Timeshare', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92103', 32.73875, -117.16107, 5.0, '$$$', 1, 2.47, 277),
(198, 'Airbnb', 'Barrio Bed Station- #1 -Walk to Convention Center', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92113', 32.70296, -117.14848, 4.55, '$', 11, 2.48, 88),
(199, 'Airbnb', 'Inn at the Park Studio', 'Resort', 'San Diego, CA, United States, San Diego, CA 92103', 32.73888, -117.16047, NULL, '$$', 0, 2.5, 182),
(200, 'Airbnb', 'GREAT LOCATION for COMIC-CON 7/18/19-7/21/19', 'Resort', 'San Diego, CA, United States, San Diego, CA 92103', 32.73898, -117.16049, NULL, '$$$', 0, 2.51, 318),
(201, 'Airbnb', 'King Studio - Inn at the Park - Comic Con', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92103', 32.73927, -117.16109, 5.0, '$$$', 1, 2.52, 264),
(202, 'Airbnb', 'Inn at the Park, San Diego California', 'Hotel', 'San Diego, CA, United States, San Diego, CA 92103', 32.73917, -117.16027, NULL, '$$', 0, 2.53, 174),
(203, 'Airbnb', 'Inn at the Park, San diego', 'Resort', 'San Diego, CA, United States, San Diego, CA 92103', 32.73908, -117.16015, NULL, '$$$', 0, 2.53, 261),
(204, 'Airbnb', 'Studio Unit @ San Diego - Inn At The Park Resort', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92103', 32.73916, -117.16037, NULL, '$$', 0, 2.53, 144),
(205, 'Airbnb', 'San Diego-WM Resort (2BDR/6Guest)', 'Resort', 'San Diego, CA, United States, San Diego, CA 92103', 32.7394, -117.16093, NULL, '$$$', 0, 2.54, 312),
(206, 'Airbnb', 'Barrio Bed Station- #6 -Walk to Convention Center', 'Hotel', 'San Diego, CA, United States, San Diego, CA 92113', 32.70395, -117.14671, 4.6, '$', 10, 2.54, 78),
(207, 'Airbnb', 'San Diego Huge Art Deco Studio at Inn at the Park', 'Resort', 'San Diego, CA, United States, San Diego, CA 92103', 32.73943, -117.16047, 5.0, '$$$', 1, 2.55, 322),
(208, 'Airbnb', 'Luxury Boutique Hotel - Perfect 4th of July in SD!', 'Resort', 'San Diego, CA, United States, San Diego, CA 92103', 32.73954, -117.16076, NULL, '$$', 0, 2.56, 171),
(209, 'Airbnb', 'Barrio Bed Station- #2 -Walk to Convention Center', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92113', 32.70332, -117.14703, 4.7, '$', 7, 2.56, 83),
(210, 'Airbnb', 'Inn At the Park Condo - 1bed/1bath', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92103', 32.73964, -117.16055, NULL, '$$', 0, 2.57, 120),
(211, 'Airbnb', 'Barrio Bed Station- #4 -Walk to Convention Center', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92113', 32.70265, -117.14684, 4.65, '$', 8, 2.62, 70),
(212, 'Airbnb', 'ITH Colive Balboa Park Female Dorm', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92103', 32.74508, -117.16038, NULL, '$', 0, 3.16, 69),
(213, 'Airbnb', 'Hillcrest Inn Hotel', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92103', 32.74508, -117.16037, NULL, '$', 0, 3.16, 59),
(214, 'Airbnb', 'Bed in 4 Bed Female Room at ITH Colive Balboa Park', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92103', 32.74536, -117.16032, NULL, '$', 0, 3.19, 76),
(215, 'Airbnb', 'Private studio room in Hillcrest', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92103', 32.74546, -117.16043, 4.65, '$', 3, 3.2, 56),
(216, 'Airbnb', 'ITH Colive Balboa Park Mixed Dorm', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92103', 32.74548, -117.1602, NULL, '$', 0, 3.21, 92),
(217, 'Airbnb', 'Bed in 4 Bed Mixed Room at ITH Colive Balboa Park', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92103', 32.74534, -117.15903, 4.0, '$', 1, 3.22, 90),
(218, 'Airbnb', 'Bed in 8 Bed Mixed Room at ITH Colive Balboa Park', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92103', 32.74569, -117.15878, NULL, '$', 0, 3.27, 69),
(219, 'Airbnb', 'La Jolla Suite - Hillcrest House Bed & Breakfast', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92103', 32.74693, -117.16381, 5.0, '$$$', 2, 3.3, 360),
(220, 'Airbnb', 'Private studio room in San Diego', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92103', 32.74651, -117.15988, 5.0, '$', 1, 3.33, 69),
(221, 'Airbnb', 'Coronado Room - Hillcrest House Bed & Breakfast', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92103', 32.74735, -117.16413, NULL, '$$', 0, 3.35, 105),
(222, 'Airbnb', 'Zoo Room - Hillcrest House Bed & Breakfast', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92103', 32.74747, -117.16431, 5.0, '$$', 3, 3.36, 114),
(223, 'Airbnb', 'ITH Colive Balboa Park 2-Bed', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92103', 32.74673, -117.15833, NULL, '$', 0, 3.39, 95),
(224, 'Airbnb', 'ITH Colive Balboa Park 8-Bed', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92103', 32.7471, -117.15845, NULL, '$', 0, 3.43, 58),
(225, 'Airbnb', 'Old Town Room - Hillcrest House Bed & Breakfast', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92103', 32.74826, -117.16451, 5.0, '$$', 1, 3.44, 134),
(226, 'Airbnb', 'Balboa B - Hillcrest House Bed & Breakfast', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92103', 32.74829, -117.16392, 4.5, '$$', 4, 3.45, 113),
(227, 'Airbnb', 'Deluxe Peace and Quiet with Pampering', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92103', 32.7483, -117.16178, 5.0, '$$', 1, 3.48, 109),
(228, 'Airbnb', 'Gaslamp Room - Hillcrest House Bed & Breakfast', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92103', 32.74886, -117.16529, 4.95, '$$', 49, 3.5, 147),
(229, 'Airbnb', 'Peace and Quiet #2', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92103', 32.74914, -117.16154, 4.75, '$$', 4, 3.58, 114),
(230, 'Airbnb', 'Hillcrest House Sleeps 10', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92103', 32.7492, -117.16063, 5.0, '$$', 1, 3.6, 170),
(231, 'Airbnb', 'Shared quite modern shared room', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92108', 32.75976, -117.16789, NULL, '$', 0, 4.7, 70),
(232, 'Airbnb', 'Old Town with large private patio', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92110', 32.7542, -117.19373, 4.75, '$', 26, 4.71, 72),
(233, 'Airbnb', 'Mission Valley 2BR Condo', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92108', 32.76057, -117.16005, 4.85, '$$', 6, 4.86, 190),
(234, 'Airbnb', 'Mission Valley Condo - 2bed/2bath Queen SN', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92108', 32.76083, -117.15971, 5.0, '$$', 2, 4.89, 167),
(235, 'Airbnb', 'San Diego - MV 1 Bdrm Condo Resort', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92108', 32.76101, -117.16054, 5.0, '$$', 3, 4.9, 132),
(236, 'Airbnb', 'Two Bedroom Sunny Beach City Adventure', 'Resort', 'San Diego, CA, United States, San Diego, CA 92108', 32.76123, -117.15998, NULL, '$$$', 0, 4.93, 348),
(237, 'Airbnb', 'Mission Valley Condo - 2 bedroom Less Desirable', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92108', 32.76121, -117.15972, NULL, '$$', 0, 4.93, 121),
(238, 'Airbnb', 'San Diego - MV 2 Bdrm Condo Resort', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92108', 32.76148, -117.15887, 4.95, '$$', 14, 4.97, 178),
(239, 'Airbnb', 'Nearby Comic Con, All Main Attractions , 6 Guests', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92108', 32.76211, -117.16004, 5.0, '$$$', 2, 5.02, 357),
(240, 'Airbnb', 'San Diego Condo - 1bed/1bath - Mission Valley', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92108', 32.76211, -117.15973, NULL, '$$', 0, 5.03, 165),
(241, 'Airbnb', 'Mission Valley Condo 4 Beds', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92108', 32.76209, -117.15912, 4.8, '$$', 5, 5.04, 136),
(242, 'Airbnb', 'Mission Valley 1BR Condo', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92108', 32.76235, -117.16012, 5.0, '$$', 1, 5.05, 165),
(243, 'Airbnb', 'Mission Valley Condo with Pool', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92108', 32.76235, -117.16004, 5.0, '$$$', 3, 5.05, 314),
(244, 'Airbnb', 'Mission Valley Accessible Condo', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92108', 32.76238, -117.15859, NULL, '$$', 0, 5.08, 129),
(245, 'Airbnb', 'Comic Con San Diego', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92108', 32.76249, -117.15848, NULL, '$$', 0, 5.09, 117),
(246, 'Airbnb', 'Mission Valley Condo - 2bed/2bath Queen', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92108', 32.76265, -117.15839, NULL, '$$', 0, 5.11, 117),
(247, 'Airbnb', 'San Diego - MV 2 Bdrm Twin Condo Resort', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92108', 32.76277, -117.15903, 4.75, '$$', 4, 5.11, 189),
(248, 'Airbnb', 'Barrio Bed Station- #7 -Walk to Convention Center', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92113', 32.69711, -117.11956, 4.9, '$', 10, 5.12, 82),
(249, 'Airbnb', 'Comic-Con stay Worldmark Mission Valley', 'Aparthotel', 'San Diego, CA, United States, San Diego, CA 92108', 32.76293, -117.15849, NULL, '$$', 0, 5.14, 150),
(250, 'Airbnb', 'San Diego Half Moon RG07', 'Resort', 'San Diego, CA, United States, San Diego, CA 92106', 32.7184, -117.22466, NULL, '$$$', 0, 5.25, 318),
(251, 'Airbnb', 'Home away from home number 2', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92111', 32.77391, -117.16347, 4.95, '$', 45, 6.29, 81),
(252, 'Airbnb', 'Crash and Dash Hostel', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92110', 32.77187, -117.19062, NULL, '$', 0, 6.39, 84),
(253, 'Airbnb', 'Mission Valley Condo - 2bed/2bath Twin', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92108', 32.77446, -117.14019, NULL, '$$', 0, 6.87, 111),
(254, 'Airbnb', 'San Diego-Mission Valley, 2 BR WorldMark Condo', 'Resort', 'San Diego, CA, United States, San Diego, CA 92108', 32.77521, -117.14093, NULL, '$$$', 0, 6.92, 377),
(255, 'Airbnb', 'Upscale luxury townhouse centrally located', 'Boutique hotel', 'San Diego, CA, United States, San Diego, CA 92108', 32.77941, -117.15003, 4.95, '$', 46, 7.1, 61),
(256, 'Airbnb', 'Luxury Room', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92110', 32.77478, -117.20333, 4.5, '$', 2, 7.15, 58),
(257, 'Airbnb', 'CITY HEIGHTS SQUARE space recommended for Airbnb', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92105', 32.75113, -117.10217, 5.0, '$$', 3, 7.25, 156),
(258, 'Airbnb', '#1 One nice Beach Condo by the shore', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92109', 32.75974, -117.24892, 4.8, '$$$', 148, 8.86, 296),
(259, 'Airbnb', '#4 DREAMY Supreme Ocean Condo', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92109', 32.75952, -117.25037, 4.85, '$$$', 148, 8.96, 237),
(260, 'Airbnb', 'SEAside suites (3) ENTIRE Pl-w/AC and parking', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92109', 32.76076, -117.25006, 4.8, '$$', 141, 9.01, 136),
(261, 'Airbnb', 'Quiet and Chill Oasis', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92117', 32.79782, -117.20627, 5.0, '$$', 3, 9.6, 129),
(262, 'Airbnb', 'Big family in San Diego', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92115', 32.76421, -117.07714, 5.0, '$', 1, 10.01, 67),
(263, 'Airbnb', 'Pacific Beach BayFront House', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92109', 32.79103, -117.24362, 5.0, '$$$', 4, 10.77, 347),
(264, 'Airbnb', 'City Heights Air Mattress', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92115', 32.75422, -117.06067, 5.0, '$', 1, 10.89, 83),
(265, 'Airbnb', 'Howard Johnson By Wyndham San Diego Chula Vista', 'Hotel', 'Chula Vista, CA, United States, Chula Vista, CA 91910', 32.64016, -117.09634, 4.4, '$', 11, 10.94, 63),
(266, 'Airbnb', 'Private Room @ Ocean Front Hostel in Pacific Beach', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79125, -117.2551, NULL, '$$', 0, 11.52, 159),
(267, 'Airbnb', 'California Dreams Hostel PB', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79727, -117.25525, 5.0, '$', 3, 12.01, 66),
(268, 'Airbnb', 'California Dreams Hostel - Private Room 2', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79709, -117.25547, 5.0, '$$', 6, 12.01, 140),
(269, 'Airbnb', 'California Dreams Hostel PB 2', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79722, -117.2557, NULL, '$', 0, 12.04, 84),
(270, 'Airbnb', 'California Dreams Hostel PB 3', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79774, -117.25544, 4.5, '$', 2, 12.06, 70),
(271, 'Airbnb', 'California Dreams Hostel PB 4', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79756, -117.25578, 5.0, '$', 6, 12.07, 59),
(272, 'Airbnb', 'California Dreams Hostel PB 5', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79756, -117.25608, 4.85, '$', 20, 12.09, 83),
(273, 'Airbnb', 'Beachfront See the Sea Ocean View 2BR Suite', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92109', 32.79655, -117.2574, NULL, '$$$', 0, 12.09, 350),
(274, 'Airbnb', 'California Dreams Hostel PB 6', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79731, -117.25684, 4.7, '$', 19, 12.12, 61),
(275, 'Airbnb', 'California Dreams Hostel OB', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79721, -117.25734, 5.0, '$', 3, 12.14, 58),
(276, 'Airbnb', 'California Dreams Hostel OB 2', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79718, -117.25739, 5.0, '$', 1, 12.14, 89),
(277, 'Airbnb', 'California Dreams Hostel PB 7', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79748, -117.2569, 4.4, '$', 5, 12.14, 55),
(278, 'Airbnb', 'California Dreams Hostel PB 8', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79706, -117.25749, 4.65, '$', 6, 12.14, 60),
(279, 'Airbnb', 'California Dreams Hostel PB 9', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.7974, -117.25746, 5.0, '$', 3, 12.16, 70),
(280, 'Airbnb', 'California Dreams Hostel OB 3', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.7988, -117.25554, NULL, '$', 0, 12.16, 65),
(281, 'Airbnb', 'California Dreams Hostel OB 4', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79874, -117.25562, 5.0, '$', 4, 12.16, 81),
(282, 'Airbnb', 'California Dreams Hostel OB 5', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79901, -117.25546, 5.0, '$', 1, 12.17, 86),
(283, 'Airbnb', 'California Dreams Hostel PB 10', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79925, -117.25559, NULL, '$', 0, 12.2, 85),
(284, 'Airbnb', 'California Dreams Hostel - Private Room 1', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79851, -117.25673, 4.65, '$$', 3, 12.21, 132),
(285, 'Airbnb', 'California Dreams Hostel OB 6', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79917, -117.25601, 5.0, '$', 1, 12.22, 80),
(286, 'Airbnb', 'California Dreams Hostel PB 11', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.7989, -117.25703, 4.7, '$', 14, 12.26, 58),
(287, 'Airbnb', 'California Dreams Hostel PB 12', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79926, -117.25676, 5.0, '$', 1, 12.27, 65),
(288, 'Airbnb', 'California Dreams Hostel PB 13', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79882, -117.25725, 5.0, '$', 1, 12.27, 79),
(289, 'Airbnb', 'California Dreams Hostel OB 7', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79911, -117.2571, 5.0, '$', 1, 12.28, 55),
(290, 'Airbnb', 'California Dreams Hostel OB 8', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79919, -117.25714, 4.5, '$', 2, 12.29, 79),
(291, 'Airbnb', 'California Dreams Hostel OB 9', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79931, -117.25711, NULL, '$', 0, 12.3, 71),
(292, 'Airbnb', 'California Dreams Hostel PB 14', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79903, -117.25761, 4.55, '$', 7, 12.31, 84),
(293, 'Airbnb', 'California Dreams Hostel OB 10', 'Hostel', 'San Diego, CA, United States, San Diego, CA 92109', 32.79921, -117.25759, 5.0, '$', 2, 12.32, 73),
(294, 'Airbnb', 'Perfect Peaceful Queen Bedroom with Private Patio', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92117', 32.83269, -117.19019, 4.7, '$', 49, 12.97, 82),
(295, 'Airbnb', 'Private Suite with ensuite Jacuzzi Bathroom', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92117', 32.83456, -117.19025, 4.55, '$', 76, 13.17, 90),
(296, 'Airbnb', 'Minutes to Everywhere San Diego!', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92117', 32.83526, -117.19045, 4.6, '$', 51, 13.25, 86),
(297, 'Airbnb', 'New Luxury Deluxe Bedroom with Private Bathroom!', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92117', 32.8359, -117.19424, 4.8, '$', 45, 13.38, 64),
(298, 'Airbnb', 'Diana''s Home', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92117', 32.83655, -117.19549, NULL, '$', 0, 13.47, 67),
(299, 'Airbnb', 'San Diego area, Chula Vista charm', 'Bed and breakfast', 'Chula Vista, CA, United States, Chula Vista, CA 91911', 32.62654, -117.06217, 5.0, '$$', 73, 14.2, 142),
(300, 'Airbnb', 'San Diego is a beautiful, vibrant, beach city.', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92120', 32.80831, -117.05425, NULL, '$$', 0, 14.71, 132),
(301, 'Airbnb', 'The Cove - The Bed & Breakfast Inn at La Jolla', 'Bed and breakfast', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84287, -117.27664, NULL, '$$$', 0, 17.21, 224),
(302, 'Airbnb', 'Bird Rock Cottage - The Bed & Breakfast Inn at La Jolla', 'Bed and breakfast', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84339, -117.27621, NULL, '$$$', 0, 17.24, 358),
(303, 'Airbnb', 'Pacific View - The Bed & Breakfast Inn at La Jolla', 'Bed and breakfast', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84286, -117.27752, NULL, '$$$', 0, 17.26, 348),
(304, 'Airbnb', 'Ellen Browning Scripps - The Bed & Breakfast Inn at La Jolla', 'Bed and breakfast', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84284, -117.27757, NULL, '$$$', 0, 17.26, 225),
(305, 'Airbnb', 'WindanSea - The Bed & Breakfast Inn at La Jolla', 'Bed and breakfast', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84267, -117.27796, NULL, '$$$', 0, 17.27, 290),
(306, 'Airbnb', 'The Shores - The Bed & Breakfast Inn at La Jolla', 'Bed and breakfast', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84287, -117.27761, NULL, '$$$', 0, 17.27, 224),
(307, 'Airbnb', 'Country Village - The Bed & Breakfast Inn at La Jolla', 'Bed and breakfast', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84301, -117.27824, NULL, '$$$', 0, 17.32, 222),
(308, 'Airbnb', 'Pelican Salon - The Bed & Breakfast Inn at La Jolla', 'Bed and breakfast', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84493, -117.27592, NULL, '$$$', 0, 17.36, 359),
(309, 'Airbnb', 'Irving Gill King Suite - The Bed & Breakfast Inn at La Jolla', 'Bed and breakfast', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84496, -117.27605, NULL, '$$$', 0, 17.37, 332),
(310, 'Airbnb', 'John Philip Sousa - The Bed & Breakfast Inn at La Jolla', 'Bed and breakfast', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84399, -117.27785, NULL, '$$$', 0, 17.38, 338),
(311, 'Airbnb', 'Holiday Suite - The Bed & Breakfast Inn at La Jolla', 'Bed and breakfast', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.8443, -117.2773, NULL, '$$$', 0, 17.38, 345),
(312, 'Airbnb', 'Fiesta - The Bed & Breakfast Inn at La Jolla', 'Bed and breakfast', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84403, -117.2777, NULL, '$$$', 0, 17.38, 250),
(313, 'Airbnb', 'Ocean Breeze - The Bed & Breakfast Inn at La Jolla', 'Bed and breakfast', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84422, -117.27771, NULL, '$$$', 0, 17.4, 224),
(314, 'Airbnb', 'Kate Sessions - The Bed & Breakfast Inn at La Jolla', 'Bed and breakfast', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84424, -117.27815, NULL, '$$$', 0, 17.42, 340),
(315, 'Airbnb', 'Spacious + Cozy Garden View Studio | Close to beaches!', 'Serviced apartment', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84598, -117.27586, NULL, '$$$', 0, 17.45, 230),
(316, 'Airbnb', 'The Garden - The Bed & Breakfast Inn at La Jolla', 'Bed and breakfast', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84495, -117.27809, NULL, '$$$', 0, 17.48, 257),
(317, 'Airbnb', 'Gorgeous Ocean Views! Elegant + Spacious Private Room, walk to beach!', 'Boutique hotel', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84632, -117.27573, NULL, '$$$', 0, 17.48, 227),
(318, 'Airbnb', 'Bright + Elegant Suite with Private Kitchenette | Walk to beach!', 'Serviced apartment', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84811, -117.27422, NULL, '$$$', 0, 17.56, 362),
(319, 'Airbnb', 'Spacious + Warm Ocean View Suite | Close to beaches!', 'Boutique hotel', 'La Jolla, CA, United States, La Jolla, CA 92037', 32.84817, -117.27418, NULL, '$$$', 0, 17.57, 227),
(320, 'Airbnb', 'Otay Ranch Chula Vista CA private bed/bath', 'Bed and breakfast', 'Chula Vista, CA, United States, Chula Vista, CA 91913', 32.61652, -117.00967, 4.95, '$', 37, 18.64, 70),
(321, 'Airbnb', 'Paris Room with Private Bathroom', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92154', 32.57705, -117.02512, NULL, '$', 0, 20.6, 80),
(322, 'Airbnb', 'Luxury Home', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92130', 32.91847, -117.22924, NULL, '$$', 0, 23.05, 120),
(323, 'Airbnb', 'Private Bedroom w/ Bathroom - Centrally Located', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92126', 32.93187, -117.14786, 4.8, '$', 67, 23.92, 91),
(324, 'Airbnb', 'Peaceful and Bright Condo with Many Amenities!', 'Serviced apartment', 'San Diego, CA, United States, San Diego, CA 92130', 32.9445, -117.23456, NULL, '$$', 0, 25.98, 136),
(325, 'Airbnb', 'Great Location near beach', 'Resort', 'Solana Beach, CA, United States, Solana Beach, CA 92075', 32.97967, -117.25815, NULL, '$$', 0, 30.33, 179),
(326, 'Airbnb', '5 mins to beach. Near Del Mar race track.', 'Resort', 'Solana Beach, CA, United States, Solana Beach, CA 92075', 32.98131, -117.25988, NULL, '$$', 0, 30.55, 181),
(327, 'Airbnb', 'Private spacious 1bed\1bath @ Rancho Bernardo', 'Bed and breakfast', 'San Diego, CA, United States, San Diego, CA 92127', 33.0385, -117.08596, NULL, '$', 0, 36.52, 57);

-- ============================================================
-- SECTION 4: PERFORMANCES (30 rows)
-- ============================================================
-- Source: Custom-built and enriched with Spotify popularity
-- day_id mapping: 1=Friday(Aug 21), 2=Saturday(Aug 22), 3=Sunday(Aug 23)
-- stage_id mapping: 1=Bahia Stage, 2=Pacific Stage, 3=Gaslamp Stage
-- ============================================================

INSERT INTO performances (performance_id, artist_name, genre, day_id, stage_id,
    start_time, end_time, origin_country, spotify_popularity, est_fee) VALUES
(1, 'Fisher', 'Tech House', 1, 1, '18:00', '19:30', 'Australia', 72, 150000),
(2, 'Chris Lake', 'Tech House', 1, 1, '19:45', '21:15', 'United Kingdom', 68, 120000),
(3, 'John Summit', 'House', 1, 1, '21:30', '23:00', 'United States', 74, 130000),
(4, 'Black Coffee', 'Afro House', 1, 2, '18:00', '19:30', 'South Africa', 70, 140000),
(5, 'Themba', 'Afro House', 1, 2, '19:45', '21:15', 'South Africa', 52, 50000),
(6, 'Enoo Napa', 'Afro Techno', 1, 2, '21:30', '23:00', 'South Africa', 44, 35000),
(7, 'Khruangbin', 'Indie/Ethnic', 1, 3, '18:00', '19:30', 'United States', 78, 160000),
(8, 'Poolside', 'Indie Dance', 1, 3, '19:45', '21:15', 'United States', 48, 40000),
(9, 'Tsha', 'Indie Dance', 1, 3, '21:30', '23:00', 'United Kingdom', 50, 45000),
(10, 'Reinier Zonneveld', 'Techno', 2, 1, '17:00', '18:30', 'Netherlands', 55, 60000),
(11, 'Adam Beyer', 'Techno', 2, 1, '18:45', '20:15', 'Sweden', 65, 110000),
(12, 'Charlotte de Witte', 'Techno', 2, 1, '20:30', '22:00', 'Belgium', 67, 120000),
(13, 'Amelie Lens', 'Techno', 2, 1, '22:15', '23:59', 'Belgium', 66, 115000),
(14, 'Culoe De Song', 'Afro House', 2, 2, '17:00', '18:30', 'South Africa', 46, 38000),
(15, 'Thievery Corporation', 'Ethnic/World', 2, 2, '18:45', '20:15', 'United States', 62, 100000),
(16, 'Nicola Cruz', 'Ethnic Techno', 2, 2, '20:30', '22:00', 'Ecuador', 54, 55000),
(17, 'Bomba Estereo', 'Ethnic/World', 2, 2, '22:15', '23:59', 'Colombia', 64, 105000),
(18, 'Mall Grab', 'Indie Dance', 2, 3, '17:00', '18:30', 'Australia', 49, 42000),
(19, 'Peggy Gou', 'Indie Dance', 2, 3, '18:45', '20:15', 'South Korea', 71, 145000),
(20, 'Four Tet', 'Indie Dance', 2, 3, '20:30', '22:00', 'United Kingdom', 69, 125000),
(21, 'Floating Points', 'Indie Dance', 2, 3, '22:15', '23:59', 'United Kingdom', 63, 100000),
(22, 'Disclosure', 'House', 3, 1, '17:00', '18:30', 'United Kingdom', 76, 175000),
(23, 'Camelphat', 'Tech House', 3, 1, '18:45', '20:15', 'United Kingdom', 68, 120000),
(24, 'Skream', 'House', 3, 1, '20:30', '22:00', 'United Kingdom', 53, 55000),
(25, 'Blond:ish', 'Afro House', 3, 2, '17:00', '18:30', 'Canada', 51, 48000),
(26, 'Bedouin', 'Ethnic Techno', 3, 2, '18:45', '20:15', 'United States', 60, 90000),
(27, 'Acid Pauli', 'Ethnic/World', 3, 2, '20:30', '22:00', 'Germany', 47, 40000),
(28, 'Bonobo', 'Indie/Ethnic', 3, 3, '17:00', '18:30', 'United Kingdom', 73, 155000),
(29, 'Booka Shade', 'Indie Dance', 3, 3, '18:45', '20:15', 'Germany', 50, 45000),
(30, 'Solomun', 'Indie Dance', 3, 3, '20:30', '22:00', 'Bosnia', 70, 140000);

-- ============================================================
-- SECTION 5: RESTAURANTS (50 rows)
-- ============================================================
-- Source: Yelp, 14 cuisine types, San Diego area
-- price_per_meal simulated using standard tier buckets:
--   $    = $8-14/meal    (fast casual, tacos)
--   $$   = $15-30/meal   (casual sit-down)
--   $$$  = $31-60/meal   (upscale dining)
--   $$$$ = $65-120/meal  (fine dining)
-- ============================================================

INSERT INTO restaurants (restaurant_id, restaurant_name, cuisine_type, rating,
    review_count, price_tier, area, address, distance_from_venue_km,
    latitude, longitude, source, price_per_meal) VALUES
(1, 'Civico 1845', 'Italian', 4.5, 4200, '$$', 'Little Italy', '1845 India St', 1.2, 32.723, -117.169, 'Google Maps / Yelp', 17),
(2, 'Bencotto Italian Kitchen', 'Italian', 4.4, 3600, '$$', 'Little Italy', '750 W Fir St', 1.1, 32.724, -117.169, 'Google Maps / Yelp', 28),
(3, 'Buon Appetito', 'Italian', 4.4, 2500, '$$$', 'Little Italy', '1609 India St', 1.0, 32.723, -117.168, 'Google Maps / Yelp', 52),
(4, 'Barbusa', 'Italian', 4.2, 3900, '$$', 'Little Italy', '1917 India St', 1.3, 32.725, -117.168, 'Google Maps / Yelp', 25),
(5, 'Filippi''s Pizza Grotto', 'Italian', 4.3, 2900, '$$', 'Little Italy', '1747 India St', 1.2, 32.724, -117.168, 'Google Maps / Yelp', 23),
(6, 'Monello', 'Italian', 4.4, 2100, '$$', 'Little Italy', '750 W Fir St', 1.1, 32.724, -117.169, 'Google Maps / Yelp', 21),
(7, 'Landini''s Pizzeria', 'Pizza', 4.5, 1800, '$', 'Little Italy', '1827 India St', 1.2, 32.724, -117.168, 'Google Maps / Yelp', 13),
(8, 'Isola Pizza Bar', 'Pizza', 4.4, 1700, '$$', 'Little Italy', '1526 India St', 0.9, 32.722, -117.168, 'Google Maps / Yelp', 25),
(9, 'Prince Street Pizza', 'Pizza', 4.5, 1300, '$', 'Downtown', '415 Market St', 2.1, 32.709, -117.161, 'Google Maps / Yelp', 9),
(10, 'Basic Bar & Pizza', 'Pizza', 4.3, 1900, '$$', 'Downtown', '410 Tenth Ave', 2.7, 32.709, -117.155, 'Google Maps / Yelp', 23),
(11, 'Puesto', 'Mexican', 4.1, 3100, '$$', 'Waterfront', '789 W Harbor Dr', 0.8, 32.709, -117.168, 'Google Maps / Yelp', 27),
(12, 'Miguel''s Cocina', 'Mexican', 4.0, 2100, '$$', 'Waterfront', '1355 N Harbor Dr', 0.7, 32.714, -117.175, 'Google Maps / Yelp', 19),
(13, 'King and Queen Cantina', 'Mexican', 4.3, 1900, '$$', 'Little Italy', '1490 Kettner Blvd', 0.8, 32.721, -117.169, 'Google Maps / Yelp', 24),
(14, 'Cocina 35', 'Mexican', 4.6, 2600, '$$', 'Downtown', '1435 Sixth Ave', 1.8, 32.72, -117.159, 'Google Maps / Yelp', 29),
(15, 'Tacos El Gordo', 'Mexican', 4.6, 9800, '$', 'Downtown', '556 Broadway', 1.8, 32.715, -117.159, 'Google Maps / Yelp', 10),
(16, 'The Taco Stand', 'Mexican', 4.6, 4700, '$', 'Downtown', '645 B St', 1.7, 32.717, -117.162, 'Google Maps / Yelp', 14),
(17, 'La Puerta', 'Mexican', 4.5, 5200, '$$', 'Gaslamp', '560 Fourth Ave', 2.1, 32.71, -117.162, 'Google Maps / Yelp', 17),
(18, 'Lolita''s Mexican Food', 'Mexican', 4.3, 2500, '$', 'Downtown', '202 Park Blvd', 2.8, 32.706, -117.154, 'Google Maps / Yelp', 8),
(19, 'Ironside Fish & Oyster', 'Seafood', 4.3, 4300, '$$', 'Little Italy', '1654 India St', 1.1, 32.724, -117.168, 'Google Maps / Yelp', 29),
(20, 'Brigantine Seafood', 'Seafood', 3.9, 1800, '$$$', 'Waterfront', '1360 N Harbor Dr', 0.7, 32.714, -117.175, 'Google Maps / Yelp', 50),
(21, 'Malibu Farm', 'American', 4.5, 2400, '$$', 'Seaport Village', '831 W Harbor Dr', 1.3, 32.707, -117.169, 'Google Maps / Yelp', 18),
(22, 'Blue Water Seafood', 'Seafood', 4.5, 4100, '$$', 'Mission Hills', '3667 India St', 2.8, 32.741, -117.17, 'Google Maps / Yelp', 17),
(23, 'The Fish Market', 'Seafood', 4.4, 5200, '$$$', 'Waterfront', '750 N Harbor Dr', 0.9, 32.711, -117.172, 'Google Maps / Yelp', 48),
(24, 'Lionfish', 'Seafood', 4.4, 1700, '$$$', 'Gaslamp', '435 Fifth Ave', 2.0, 32.709, -117.161, 'Google Maps / Yelp', 37),
(25, 'Sally''s Fish House', 'Seafood', 4.4, 2000, '$$$', 'Marina', '1 Market Pl', 1.7, 32.706, -117.167, 'Google Maps / Yelp', 47),
(26, 'Queenstown Public House', 'American', 4.4, 2800, '$$', 'Little Italy', '1557 Columbia St', 0.9, 32.722, -117.17, 'Google Maps / Yelp', 23),
(27, 'Craft & Commerce', 'American', 4.4, 3000, '$$', 'Little Italy', '675 W Beech St', 1.1, 32.723, -117.167, 'Google Maps / Yelp', 19),
(28, 'Juniper & Ivy', 'American', 4.5, 3400, '$$$', 'Little Italy', '2228 Kettner Blvd', 1.6, 32.726, -117.171, 'Google Maps / Yelp', 60),
(29, 'Herb & Wood', 'American', 4.5, 3100, '$$$', 'Little Italy', '2210 Kettner Blvd', 1.5, 32.726, -117.171, 'Google Maps / Yelp', 42),
(30, 'Carnitas'' Snack Shack', 'American', 4.4, 2600, '$$', 'Embarcadero', '1004 N Harbor Dr', 0.8, 32.711, -117.173, 'Google Maps / Yelp', 17),
(31, 'Rustic Root', 'American', 4.3, 2600, '$$$', 'Gaslamp', '535 Fifth Ave', 2.0, 32.709, -117.16, 'Google Maps / Yelp', 59),
(32, 'Garage Kitchen', 'American', 4.2, 1600, '$$', 'Gaslamp', '655 Fourth Ave', 2.1, 32.71, -117.162, 'Google Maps / Yelp', 22),
(33, 'Harbor Breakfast', 'Breakfast', 4.3, 1400, '$', 'Waterfront', '1355 N Harbor Dr', 0.8, 32.714, -117.175, 'Google Maps / Yelp', 10),
(34, 'Morning Glory', 'Brunch', 4.2, 6700, '$$', 'Little Italy', '550 W Date St', 1.2, 32.724, -117.166, 'Google Maps / Yelp', 24),
(35, 'Richard Walker''s Pancake House', 'Breakfast', 4.5, 3500, '$$', 'Downtown', '520 Front St', 1.5, 32.711, -117.165, 'Google Maps / Yelp', 20),
(36, 'Cafe 222', 'Breakfast', 4.5, 2100, '$', 'Downtown', '222 Island Ave', 2.2, 32.708, -117.162, 'Google Maps / Yelp', 11),
(37, 'Pappalecco', 'Cafe', 4.6, 2200, '$$', 'Little Italy', '1602 State St', 1.0, 32.723, -117.167, 'Google Maps / Yelp', 24),
(38, 'Cafe Gratitude', 'Vegan', 4.5, 1700, '$$', 'Little Italy', '1980 Kettner Blvd', 1.4, 32.725, -117.17, 'Google Maps / Yelp', 15),
(39, 'Extraordinary Desserts', 'Dessert', 4.6, 5400, '$$', 'Bankers Hill', '2870 Fourth Ave', 2.0, 32.733, -117.161, 'Google Maps / Yelp', 24),
(40, 'Salt & Straw', 'Dessert', 4.6, 2800, '$', 'Little Italy', '1670 India St', 1.1, 32.724, -117.168, 'Google Maps / Yelp', 13),
(41, 'Underbelly', 'Ramen', 4.2, 2200, '$$', 'Little Italy', '750 W Fir St', 1.1, 32.724, -117.169, 'Google Maps / Yelp', 18),
(42, 'Cloak & Petal', 'Japanese', 4.4, 2700, '$$', 'Little Italy', '1953 India St', 1.3, 32.725, -117.168, 'Google Maps / Yelp', 19),
(43, 'Harumama', 'Japanese', 4.5, 2900, '$$', 'Little Italy', '1901 Columbia St', 1.2, 32.724, -117.169, 'Google Maps / Yelp', 23),
(44, 'Sushi Deli 3', 'Japanese', 4.4, 3200, '$$', 'Downtown', '798 Sixth Ave', 2.2, 32.713, -117.159, 'Google Maps / Yelp', 18),
(45, 'Sushi Ota', 'Japanese', 4.7, 3100, '$$$', 'Pacific Beach', '4529 Mission Bay Dr', 10.5, 32.802, -117.216, 'Google Maps / Yelp', 59),
(46, 'Born and Raised', 'Steakhouse', 4.5, 3300, '$$$$', 'Little Italy', '1909 India St', 1.3, 32.725, -117.168, 'Google Maps / Yelp', 71),
(47, 'Fogo de Chão', 'Brazilian', 4.5, 3000, '$$$$', 'Gaslamp', '668 Sixth Ave', 2.2, 32.709, -117.158, 'Google Maps / Yelp', 112),
(48, 'The Crack Shack', 'Fast Food', 4.4, 5100, '$', 'Little Italy', '2266 Kettner Blvd', 1.6, 32.726, -117.17, 'Google Maps / Yelp', 12),
(49, 'Ballast Point Brewing', 'Brewery', 4.5, 3000, '$$', 'Little Italy', '2215 India St', 1.5, 32.726, -117.169, 'Google Maps / Yelp', 19),
(50, 'Edgewater Grill', 'American', 4.3, 1400, '$$', 'Waterfront', '861 W Harbor Dr', 1.2, 32.707, -117.17, 'Google Maps / Yelp', 23);

-- ============================================================

-- SECTION 6: FREE-TIME ACTIVITIES (16 rows)
-- ============================================================
-- Source: City of San Diego + official sources
-- Curated San Diego activities used by the Shiny planner.
-- Includes parks, beaches, museums, cultural attractions, and
-- other free-time options with price, hours, and location data.
-- ============================================================

INSERT INTO public.free_time_activities (
    activity_id,
    activity_name,
    activity_type,
    activity_location,
    operating_hours,
    adult_price_usd,
    price_category,
    is_free_or_low_cost,
    description,
    price_notes,
    primary_source,
    hours_source_url,
    price_source_url,
    verified_date,
    latitude,
    longitude
) VALUES
(1, 'Balboa Park', 'Park / Cultural District', '1549 El Prado, San Diego, CA 92101', 'Outdoor park access generally daily; individual venues set their own hours', 0.00, 'Free with paid options', TRUE, 'Large urban park with gardens, architecture, museums, trails, and cultural attractions.', 'General park access is free. Museums, attractions, programs, and parking may charge separately.', 'City of San Diego', 'https://www.sandiego.gov/park-and-recreation/parks/regional/balboa', 'https://www.sandiego.gov/parking/balboapark', '2026-07-30', 32.731100, -117.146700),
(2, 'Mission Bay Park', 'Waterfront Park', '2688 E Mission Bay Dr, San Diego, CA 92109', 'Most areas are accessible daily; individual lots and facilities have posted hours', 0.00, 'Free with paid options', TRUE, 'Large waterfront recreation area with beaches, paths, picnic spaces, playgrounds, and water activities.', 'General park access is free. Rentals, permits, lessons, and some activities may charge separately.', 'City of San Diego', 'https://www.sandiego.gov/park-and-recreation/parks/regional/missionbay', '', '2026-07-30', 32.775700, -117.234300),
(3, 'Sunset Cliffs Natural Park', 'Natural / Scenic Park', 'Ladera St & Sunset Cliffs Blvd, San Diego, CA 92107', 'Open 24 hours daily', 0.00, 'Free', TRUE, 'Coastal natural park known for bluff-top views, walking areas, tide pools, and sunsets.', 'No general admission fee. Visitors should follow posted safety and access rules.', 'City of San Diego', 'https://www.sandiego.gov/park-and-recreation/parks/regional/shoreline/sunset', '', '2026-07-30', 32.719200, -117.253100),
(4, 'La Jolla Shores Beach', 'Beach', '8300 Camino Del Oro, La Jolla, CA 92037', 'Beach is generally accessible daily; parking and lifeguard coverage vary', 0.00, 'Free with paid options', TRUE, 'Wide sandy beach popular for swimming, kayaking, beginner surfing, picnics, and walking.', 'General beach access is free. Parking, equipment rentals, lessons, and tours may cost extra.', 'City of San Diego', 'https://www.sandiego.gov/lifeguards/beaches/shores', '', '2026-07-30', 32.857100, -117.256700),
(5, 'Old Town San Diego State Historic Park', 'Historic / Cultural Park', '4002 Wallace St, San Diego, CA 92110', 'Visitor Center and select museums: daily 10:00 AM–5:00 PM', 0.00, 'Free with paid options', TRUE, 'Historic district with preserved buildings, museums, exhibits, shops, and cultural demonstrations.', 'General park and museum admission is free. Guided tours and some activities may charge separately.', 'California State Parks', 'https://www.parks.ca.gov/oldtownsandiego', 'https://www.parks.ca.gov/?page_id=24801', '2026-07-30', 32.754200, -117.196100),
(6, 'Cabrillo National Monument', 'National Monument / Scenic Site', '1800 Cabrillo Memorial Dr, San Diego, CA 92106', 'Daily 9:00 AM–5:00 PM; closed Thanksgiving and Christmas', 10.00, 'Low cost', TRUE, 'National monument offering harbor views, coastal scenery, history exhibits, trails, and seasonal tide pools.', '$10 per person entering by foot or bicycle; vehicle passes have a different fee and cover occupants.', 'National Park Service', 'https://www.nps.gov/cabr/planyourvisit/hours.htm', 'https://www.nps.gov/cabr/planyourvisit/fees.htm', '2026-07-30', 32.672300, -117.241600),
(7, 'Japanese Friendship Garden and Museum', 'Garden / Cultural Attraction', '2215 Pan American Rd E, San Diego, CA 92101', 'Daily 10:00 AM–7:00 PM; last admission 6:00 PM', 16.00, 'Low cost', TRUE, 'Japanese garden featuring landscaped paths, koi ponds, cultural exhibits, and seasonal displays.', 'Adult general admission listed at $16; discounts may be available for students, seniors, and children.', 'Japanese Friendship Garden and Museum', 'https://www.niwa.org/visit', '', '2026-07-30', 32.729800, -117.150300),
(8, 'Fleet Science Center', 'Science Museum', '1875 El Prado, San Diego, CA 92101', 'Daily 10:00 AM–5:00 PM; selected extended-hour events', 21.95, 'Moderate', FALSE, 'Interactive science museum with hands-on exhibits and a giant-dome theater.', 'Adult admission listed at $21.95; special programs or films may have separate pricing.', 'Fleet Science Center', 'https://www.fleetscience.org/visit-fleet-science-center', '', '2026-07-30', 32.730800, -117.147000),
(9, 'Museum of Contemporary Art San Diego – La Jolla', 'Art Museum', '700 Prospect St, La Jolla, CA 92037', 'Thu–Sat 11:00 AM–7:00 PM; Sun 11:00 AM–5:00 PM; Mon–Wed closed', 25.00, 'Moderate', FALSE, 'Contemporary art museum with indoor galleries, outdoor spaces, and coastal views.', 'General adult admission listed at $25. Free admission is offered on selected monthly days.', 'Museum of Contemporary Art San Diego', 'https://mcasd.org/visit/mcasd', '', '2026-07-30', 32.844000, -117.278400),
(10, 'San Diego Natural History Museum', 'Natural History Museum', '1788 El Prado, San Diego, CA 92101', 'Daily 10:00 AM–5:00 PM; selected Fridays may have extended hours', 24.95, 'Moderate', FALSE, 'Natural history museum featuring regional biodiversity, fossils, exhibitions, and educational programs.', 'Adult daytime admission listed at $24.95; selected evening admission may be lower.', 'San Diego Natural History Museum', 'https://www.sdnhm.org/visit/', '', '2026-07-30', 32.732100, -117.147300),
(11, 'The New Children''s Museum', 'Children''s / Interactive Museum', '200 W Island Ave, San Diego, CA 92101', 'Mon and Wed–Sun 9:00 AM–4:00 PM; Tue closed', 24.00, 'Moderate', FALSE, 'Interactive contemporary-art museum designed around creative play and hands-on installations.', 'Adult admission listed at $24; children age one and older have separate admission pricing.', 'The New Children''s Museum', 'https://thinkplaycreate.org/visit/', 'https://thinkplaycreate.org/museum-faqs/', '2026-07-30', 32.710600, -117.164900),
(12, 'Maritime Museum of San Diego', 'Maritime Museum', '1492 N Harbor Dr, San Diego, CA 92101', 'Daily 10:00 AM–5:00 PM; last entry 4:00 PM', 28.00, 'Moderate', FALSE, 'Waterfront museum offering access to historic ships and maritime exhibits.', 'Adult walk-up admission listed at $28; online price includes ticketing fees and may be higher.', 'Maritime Museum of San Diego', 'https://sdmaritime.org/visit/general-admission/', '', '2026-07-30', 32.720900, -117.173100),
(13, 'Birch Aquarium at Scripps', 'Aquarium', '2300 Expedition Way, La Jolla, CA 92037', 'Opens daily at 9:00 AM; closing time varies by season', 34.95, 'Moderate', FALSE, 'Public aquarium featuring marine life, ocean-science exhibits, tide-pool views, and daily programs.', 'Adult online admission starts around $34.95 and may vary by date; verify the selected festival date.', 'Birch Aquarium at Scripps', 'https://aquarium.ucsd.edu/plan-your-visit', '', '2026-07-30', 32.866200, -117.250500),
(14, 'USS Midway Museum', 'Naval / History Museum', '910 N Harbor Dr, San Diego, CA 92101', 'Daily 10:00 AM–5:00 PM; last admission 4:00 PM', 39.00, 'Moderate', FALSE, 'Aircraft-carrier museum with restored aircraft, exhibits, audio tours, and flight-deck views.', 'Adult online admission listed at $39; at-the-door admission is higher.', 'USS Midway Museum', 'https://www.midway.org/visit/know-before-you-go', '', '2026-07-30', 32.713700, -117.175100),
(15, 'Belmont Park', 'Amusement / Recreation', '3146 Mission Blvd, San Diego, CA 92109', 'Hours vary by date and attraction; check the official daily calendar', 64.96, 'Premium', FALSE, 'Beachfront amusement area with rides, games, attractions, dining, and the historic Giant Dipper.', 'Entry to the park is free. The listed price represents the standard Ride & Play wristband; promotions may reduce it.', 'Belmont Park', 'https://www.belmontpark.com/tickets-reservation', 'https://www.belmontpark.com/park-info', '2026-07-30', 32.770000, -117.251400),
(16, 'San Diego Zoo', 'Zoo / Wildlife Attraction', '2920 Zoo Dr, San Diego, CA 92101', 'Open daily; summer 2026 hours shown as 9:00 AM–8:00 PM through Aug. 9, then verify daily hours', 78.00, 'Premium', FALSE, 'Major wildlife attraction in Balboa Park with animal habitats, a guided bus tour, and aerial tram.', 'Adult one-day Any Day admission listed at $78; selected Value Days may be discounted.', 'San Diego Zoo Wildlife Alliance', 'https://zoo.sandiegozoo.org/plan-your-visit', 'https://zoo.sandiegozoo.org/tickets', '2026-07-30', 32.735300, -117.149000);

-- SECTION 7: TRANSPORTATION
-- ============================================================
-- Source: San Diego MTS GTFS
-- Transportation data includes:
--   1. transport_routes
--   2. transport_stops
--   3. transport_trips
--   4. stop_times
--   5. accommodation_transit_estimates
-- ============================================================


-- ------------------------------------------------------------
-- 7.1 Transport Routes
-- Source file: routes.txt
-- ------------------------------------------------------------

COPY public.transport_routes (
    route_id,
    agency_id,
    route_short_name,
    route_long_name,
    route_type,
    route_url,
    route_color,
    route_text_color,
    route_group,
    route_pattern1,
    route_pattern2
)
FROM '/path/to/routes.txt'
WITH (
    FORMAT CSV,
    HEADER TRUE
);


-- ------------------------------------------------------------
-- 7.2 Transport Stops
-- Source file: stops.txt
-- ------------------------------------------------------------

COPY public.transport_stops (
    stop_id,
    stop_code,
    stop_name,
    stop_lat,
    stop_lon,
    zone_id,
    stop_url,
    location_type,
    parent_station,
    wheelchair_boarding,
    intersection_code,
    reference_place,
    stop_name_short,
    stop_place
)
FROM '/path/to/stops.txt'
WITH (
    FORMAT CSV,
    HEADER TRUE
);


-- ------------------------------------------------------------
-- 7.3 Transport Trips
-- Source file: transport_trips_import_ready.csv
--
-- The original GTFS trips file contained mixed route IDs,
-- including text values such as 'COR'. An import-ready version
-- was used to avoid automatic numeric type inference errors.
-- ------------------------------------------------------------

COPY public.transport_trips (
    route_id,
    service_id,
    trip_id,
    trip_headsign,
    direction_id,
    block_id,
    shape_id,
    wheelchair_accessible,
    bikes_allowed,
    direction_name,
    trip_bikes_allowed,
    trip_headsign_short
)
FROM '/path/to/transport_trips_import_ready.csv'
WITH (
    FORMAT CSV,
    HEADER TRUE
);


-- ------------------------------------------------------------
-- 7.4 Stop Times
-- Source file: stop_times.txt
-- ------------------------------------------------------------

COPY public.stop_times (
    trip_id,
    arrival_time,
    departure_time,
    stop_id,
    stop_sequence,
    stop_headsign,
    pickup_type,
    drop_off_type,
    shape_dist_traveled,
    timepoint
)
FROM '/path/to/stop_times.txt'
WITH (
    FORMAT CSV,
    HEADER TRUE
);


-- ------------------------------------------------------------
-- 7.5 Accommodation Transit Estimates
-- 327 lodging options x 3 festival days = 981 rows
--
-- These estimates connect each lodging option and festival day
-- with an estimated trip to Waterfront Park.
-- ------------------------------------------------------------

COPY public.accommodation_transit_estimates (
    estimate_id,
    lodging_id,
    day_id,
    departure_time,
    mode,
    estimated_minutes,
    num_stops,
    origin_stop,
    destination_stop,
    trip_id
)
FROM '/path/to/accommodation_transit_estimates_FINAL_FK_READY.csv'
WITH (
    FORMAT CSV,
    HEADER TRUE,
    NULL ''
);


-- ============================================================

-- ============================================================

-- SECTION 8: CREATIVE FEATURE — Check-In Leaderboard & Budget Battle
-- Author: Ming
-- ============================================================
-- Part 1: Load Script
--   Inserts 6 demo attendees (one per team member) covering
--   the full range of check-in and bonus scenarios (0-22 pts):
--     Adel     — all 3 bonuses (Stage + Foodie + Explorer)
--     Xiaobei  — 2 bonuses (Stage + Foodie)
--     Kashvi   — 1 bonus (Explorer only)
--     Zahide   — check-ins present, no bonus triggered
--     Kaisheng — minimal check-ins, no bonus
--     Mingjian — no check-ins (baseline / zero score case)
--
-- Part 2: Query Logic
--   6 queries computing base score, 3 bonuses, total spend,
--   and the final leaderboard ranked by value score.
-- ============================================================

-- ── 8.1 Attendees ────────────────────────────────────────────

INSERT INTO attendees (attendee_id, attendee_name, total_budget, chosen_lodging_id)
VALUES (1, 'Adel', 500, 4),
       (2, 'Xiaobei', 500, 2),
       (3, 'Kashvi', 500, 4),
       (4, 'Zahide', 500, 2),
       (5, 'Kaisheng', 500, 2),
       (6, 'Mingjian', 500, 2);

-- ------------------------------------------------------------
-- 8.2 Performance Check-Ins
-- ------------------------------------------------------------
-- Adel and Xiaobei each cover all 3 stages (triggers Stage Bonus).
-- Kashvi checks in twice at the same stage (does not trigger).
-- Zahide covers 2 of 3 stages (does not trigger).
-- Kaisheng checks in once. Mingjian has no records.

INSERT INTO performance_checkins (checkin_id, attendee_id, performance_id, checkin_time)
VALUES (1, 1, 1,  '2026-08-21 18:00:00'),
       (2, 1, 4,  '2026-08-22 19:00:00'),
       (3, 1, 7,  '2026-08-23 20:00:00'),
       (4, 2, 2,  '2026-08-21 18:30:00'),
       (5, 2, 5,  '2026-08-22 19:30:00'),
       (6, 2, 8,  '2026-08-23 20:30:00'),
       (7, 3, 10, '2026-08-21 17:00:00'),
       (8, 3, 11, '2026-08-21 17:30:00'),
       (9, 4, 22, '2026-08-21 18:00:00'),
       (10, 4, 25, '2026-08-22 19:00:00'),
       (11, 5, 3,  '2026-08-21 12:00:00');

-- ------------------------------------------------------------
-- 8.3 Restaurant Check-Ins
-- ------------------------------------------------------------
-- Adel and Xiaobei each cover 5 distinct cuisine types (triggers
-- Foodie Bonus). Kashvi and Zahide fall short of 5 cuisines.
-- Kaisheng checks in once. Mingjian has no records.

INSERT INTO restaurant_checkins (checkin_id, attendee_id, restaurant_id, checkin_time)
VALUES (1, 1, 1,  '2026-08-21 12:00:00'),
       (2, 1, 11, '2026-08-21 19:00:00'),
       (3, 1, 42, '2026-08-22 12:00:00'),
       (4, 1, 19, '2026-08-22 19:00:00'),
       (5, 1, 7,  '2026-08-23 12:00:00'),
       (6, 2, 2,  '2026-08-21 12:30:00'),
       (7, 2, 12, '2026-08-21 19:30:00'),
       (8, 2, 43, '2026-08-22 12:30:00'),
       (9, 2, 20, '2026-08-22 19:30:00'),
       (10, 2, 9,  '2026-08-23 12:30:00'),
       (11, 3, 11, '2026-08-21 13:00:00'),
       (12, 3, 13, '2026-08-21 20:00:00'),
       (13, 4, 4,  '2026-08-21 13:30:00'),
       (14, 4, 20, '2026-08-22 20:00:00'),
       (15, 5, 5,  '2026-08-21 13:00:00');

-- ------------------------------------------------------------
-- 8.4 Activity Check-Ins
-- ------------------------------------------------------------
-- Adel and Kashvi each cover all 7 free/low-cost activities
-- (triggers Explorer Bonus). Xiaobei and Zahide fall short.
-- Kaisheng checks in once. Mingjian has no records.

INSERT INTO activity_checkins (checkin_id, attendee_id, activity_id, checkin_time)
VALUES (1, 1, 1, '2026-08-21 10:00:00'),
       (2, 1, 2, '2026-08-21 11:00:00'),
       (3, 1, 3, '2026-08-21 13:00:00'),
       (4, 1, 4, '2026-08-22 10:00:00'),
       (5, 1, 5, '2026-08-22 11:00:00'),
       (6, 1, 6, '2026-08-22 13:00:00'),
       (7, 1, 7, '2026-08-23 10:00:00'),
       (8, 2, 1, '2026-08-21 10:30:00'),
       (9, 2, 2, '2026-08-21 11:30:00'),
       (10, 2, 3, '2026-08-21 13:30:00'),
       (11, 3, 1, '2026-08-21 09:00:00'),
       (12, 3, 2, '2026-08-21 09:30:00'),
       (13, 3, 3, '2026-08-21 10:00:00'),
       (14, 3, 4, '2026-08-22 09:00:00'),
       (15, 3, 5, '2026-08-22 09:30:00'),
       (16, 3, 6, '2026-08-22 10:00:00'),
       (17, 3, 7, '2026-08-23 09:00:00'),
       (18, 4, 1, '2026-08-21 10:00:00'),
       (19, 4, 2, '2026-08-21 10:30:00'),
       (20, 4, 3, '2026-08-21 11:00:00'),
       (21, 5, 4, '2026-08-21 10:00:00');


-- ── Query Logic ─────────────────────────────────────────────

-- ============================================================
-- Query 1: Base Score
-- 1 point per unique check-in (distinct performance, restaurant, activity)
-- ============================================================

  WITH perf_base --distinct performances checked in per attendee
    AS (SELECT attendee_id
             , count(DISTINCT performance_id) n
          FROM performance_checkins
         GROUP BY 1),
       rest_base --distinct restaurants checked in per attendee
    AS (SELECT attendee_id
             , count(DISTINCT restaurant_id) n
          FROM restaurant_checkins
         GROUP BY 1),
       act_base --distinct activities checked in per attendee
    AS (SELECT attendee_id
             , count(DISTINCT activity_id) n
          FROM activity_checkins
         GROUP BY 1)
SELECT attendee_id
     , coalesce(p.n, 0) + coalesce(r.n, 0) + coalesce(a.n, 0) base_score
  FROM attendees
  LEFT JOIN perf_base p USING (attendee_id)
  LEFT JOIN rest_base r USING (attendee_id)
  LEFT JOIN act_base a USING (attendee_id);


-- ============================================================
-- Query 2: Stage Bonus (+2 points)
-- Awarded when attendee checks in at all 3 stages (Bahia, Pacific, Gaslamp)
-- ============================================================

  WITH stage_cov --distinct stages checked in per attendee
    AS (SELECT attendee_id
             , count(DISTINCT stage_id) n_stages
          FROM performance_checkins
          JOIN performances USING (performance_id)
         GROUP BY 1)
SELECT attendee_id
     , CASE WHEN n_stages = 3 THEN 2 ELSE 0 END stage_bonus
  FROM stage_cov;

-- ============================================================
-- Query 3: Foodie Bonus (+2 points)
-- Awarded after checking in at 5 different cuisine types
-- ============================================================

  WITH cuisine_cov --distinct cuisine types checked in per attendee
    AS (SELECT attendee_id
             , count(DISTINCT cuisine_type) n_cuisines
          FROM restaurant_checkins
          JOIN restaurants USING (restaurant_id)
         GROUP BY 1)
SELECT attendee_id
     , CASE WHEN n_cuisines >= 5 THEN 2 ELSE 0 END foodie_bonus
  FROM cuisine_cov;


-- ============================================================
-- Query 4: Explorer Bonus (+3 points)
-- Awarded after checking in at ALL free/low-cost activities
-- Note: total count is pulled dynamically (not hardcoded),
--   so this stays correct even if Adel's dataset changes again
-- ============================================================

  WITH free_total --total number of free/low-cost activities available
    AS (SELECT count(*) n_total
          FROM free_time_activities
         WHERE is_free_or_low_cost = TRUE),
       explorer_cov --distinct free/low-cost activities checked in per attendee
    AS (SELECT attendee_id
             , count(DISTINCT activity_id) n_free
          FROM activity_checkins
          JOIN free_time_activities USING (activity_id)
         WHERE is_free_or_low_cost = TRUE
         GROUP BY 1)
SELECT attendee_id
     , CASE WHEN n_free = (SELECT n_total FROM free_total) THEN 3 ELSE 0 END explorer_bonus
  FROM explorer_cov;


-- ============================================================
-- Query 5: Total Spend Estimate (lodging + food)
-- NOTE: price_tier symbols ($, $$, $$$, $$$$) are mapped to
--   estimated dollar amounts below. These numbers are placeholder
--   assumptions and should be confirmed with Kashvi/Xiaobei
--   before finalizing.
-- ============================================================

  WITH lodging_cost --estimated lodging spend based on chosen lodging's price tier
    AS (SELECT att.attendee_id
             , CASE a.price_tier
                 WHEN '$'   THEN 75   --Low tier estimate
                 WHEN '$$'  THEN 150  --Mid tier estimate
                 WHEN '$$$' THEN 250  --High tier estimate
               END lodging_spend
          FROM attendees att
          JOIN accommodations a ON a.lodging_id = att.chosen_lodging_id),
       restaurant_cost --estimated food spend, summed across all restaurant check-ins
    AS (SELECT rc.attendee_id
             , sum(CASE r.price_tier
                     WHEN '$'    THEN 15  --price tier $ estimate
                     WHEN '$$'   THEN 35  --price tier $$ estimate
                     WHEN '$$$'  THEN 60  --price tier $$$ estimate
                     WHEN '$$$$' THEN 90  --price tier $$$$ estimate
                   END) restaurant_spend
          FROM restaurant_checkins rc
          JOIN restaurants r USING (restaurant_id)
         GROUP BY 1)
SELECT attendee_id
     , coalesce(lodging_spend, 0) + coalesce(restaurant_spend, 0) total_spend
  FROM attendees
  LEFT JOIN lodging_cost USING (attendee_id)
  LEFT JOIN restaurant_cost USING (attendee_id);


-- ============================================================
-- Query 6: Final Leaderboard
-- Combines base score + all 3 bonuses into experience_score,
--   combines total_spend, then computes:
--   Value Ranking = experience_score / total_spend
--   Leaderboard Rank = rank ordered by Value Ranking (highest first)
-- ============================================================

  WITH perf_base --distinct performances checked in per attendee
    AS (SELECT attendee_id, count(DISTINCT performance_id) n
          FROM performance_checkins GROUP BY 1),
       rest_base --distinct restaurants checked in per attendee
    AS (SELECT attendee_id, count(DISTINCT restaurant_id) n
          FROM restaurant_checkins GROUP BY 1),
       act_base --distinct activities checked in per attendee
    AS (SELECT attendee_id, count(DISTINCT activity_id) n
          FROM activity_checkins GROUP BY 1),
       stage_cov --distinct stages checked in per attendee (for Stage Bonus)
    AS (SELECT attendee_id, count(DISTINCT stage_id) n_stages
          FROM performance_checkins
          JOIN performances USING (performance_id)
         GROUP BY 1),
       cuisine_cov --distinct cuisine types checked in per attendee (for Foodie Bonus)
    AS (SELECT attendee_id, count(DISTINCT cuisine_type) n_cuisines
          FROM restaurant_checkins
          JOIN restaurants USING (restaurant_id)
         GROUP BY 1),
       free_total --total number of free/low-cost activities available
    AS (SELECT count(*) n_total
          FROM free_time_activities
         WHERE is_free_or_low_cost = TRUE),
       explorer_cov --distinct free/low-cost activities checked in per attendee (for Explorer Bonus)
    AS (SELECT attendee_id, count(DISTINCT activity_id) n_free
          FROM activity_checkins
          JOIN free_time_activities USING (activity_id)
         WHERE is_free_or_low_cost = TRUE
         GROUP BY 1),
       lodging_cost --estimated lodging spend based on chosen lodging's price tier
    AS (SELECT att.attendee_id
             , CASE a.price_tier
                 WHEN '$'   THEN 75
                 WHEN '$$'  THEN 150
                 WHEN '$$$' THEN 250
               END lodging_spend
          FROM attendees att
          JOIN accommodations a ON a.lodging_id = att.chosen_lodging_id),
       restaurant_cost --estimated food spend, summed across all restaurant check-ins
    AS (SELECT rc.attendee_id
             , sum(CASE r.price_tier
                     WHEN '$'    THEN 15
                     WHEN '$$'   THEN 35
                     WHEN '$$$'  THEN 60
                     WHEN '$$$$' THEN 90
                   END) restaurant_spend
          FROM restaurant_checkins rc
          JOIN restaurants r USING (restaurant_id)
         GROUP BY 1),
       combined --per-attendee experience score and total spend, before ranking
    AS (SELECT att.attendee_id
             , att.attendee_name
             , coalesce(p.n, 0) + coalesce(r.n, 0) + coalesce(a.n, 0)
                 + CASE WHEN sc.n_stages = 3 THEN 2 ELSE 0 END          --Stage Bonus
                 + CASE WHEN cc.n_cuisines >= 5 THEN 2 ELSE 0 END       --Foodie Bonus
                 + CASE WHEN ec.n_free = (SELECT n_total FROM free_total) THEN 3 ELSE 0 END --Explorer Bonus
                 AS experience_score
             , coalesce(lc.lodging_spend, 0) + coalesce(rcst.restaurant_spend, 0) AS total_spend
          FROM attendees att
          LEFT JOIN perf_base p USING (attendee_id)
          LEFT JOIN rest_base r USING (attendee_id)
          LEFT JOIN act_base a USING (attendee_id)
          LEFT JOIN stage_cov sc USING (attendee_id)
          LEFT JOIN cuisine_cov cc USING (attendee_id)
          LEFT JOIN explorer_cov ec USING (attendee_id)
          LEFT JOIN lodging_cost lc USING (attendee_id)
          LEFT JOIN restaurant_cost rcst USING (attendee_id))
SELECT attendee_id
     , attendee_name
     , experience_score
     , total_spend
     , CASE WHEN total_spend = 0 THEN NULL             --avoid divide-by-zero
            ELSE round(experience_score::NUMERIC / total_spend, 4)
       END value_ranking
     , RANK()
         OVER (ORDER BY CASE WHEN total_spend = 0 THEN 0
                              ELSE experience_score::NUMERIC / total_spend
                         END DESC) leaderboard_rank
  FROM combined
 ORDER BY leaderboard_rank;


-- ============================================================
-- END OF FILE
-- ============================================================

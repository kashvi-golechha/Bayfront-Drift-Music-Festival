# ============================================================
# Bayfront Drift - San Diego festival weekend planner
# R Shiny + PostgreSQL (musicfest4)
#
# One-time package install:
#   install.packages(c(
#     "shiny", "bslib", "DBI", "RPostgres", "DT",
#     "leaflet", "shinyjs"
#   ))
#
# Connection is read from environment variables (see connect_to_db).
# Set them once in a .Renviron file next to this app, e.g.:
#   MUSICFEST_DB_HOST=...
#   MUSICFEST_DB_PORT=25061
#   MUSICFEST_DB_NAME=musicfest4
#   MUSICFEST_DB_USER=proj4
#   MUSICFEST_DB_PASSWORD=...
# ============================================================

library(shiny)
library(bslib)
library(DBI)
library(RPostgres)
library(DT)
library(leaflet)
library(shinyjs)

# ------------------------------------------------------------
# Configuration (edit these in one place)
# ------------------------------------------------------------

# Festival venue anchor - used for the map marker and as the
# distance reference the datasets were built against.
VENUE <- list(
  name = "Waterfront Park",
  lat  = 32.7205,
  lng  = -117.1712
)

FESTIVAL <- list(
  name     = "Bayfront Music Festival",
  dates    = "August 21-23, 2026",
  location = "Waterfront Park, San Diego"
)


# ------------------------------------------------------------
# Database helpers
# ------------------------------------------------------------

connect_to_db <- function() {
  dbConnect(
    RPostgres::Postgres(),
    host     = Sys.getenv("MUSICFEST_DB_HOST"),
    port     = as.integer(Sys.getenv("MUSICFEST_DB_PORT")),
    dbname   = Sys.getenv("MUSICFEST_DB_NAME"),
    user     = Sys.getenv("MUSICFEST_DB_USER"),
    password = Sys.getenv("MUSICFEST_DB_PASSWORD"),
    sslmode  = "require"
  )
}

# Run a query and never let a failure crash the app.
safe_query <- function(con, sql, fallback = data.frame()) {
  if (is.null(con) || !dbIsValid(con)) return(fallback)
  tryCatch(
    dbGetQuery(con, sql),
    error = function(e) {
      warning(e$message)
      fallback
    }
  )
}

# Count rows in a known (constant) table name. Missing table -> 0.
count_rows <- function(con, table) {
  res <- safe_query(
    con,
    sprintf("SELECT COUNT(*) AS n FROM public.%s", table),
    data.frame(n = 0)
  )
  if (nrow(res) == 0) 0L else as.integer(res$n[1])
}

# Check whether a column exists.
column_exists <- function(con, table, column) {
  if (is.null(con) || !dbIsValid(con)) return(FALSE)
  res <- tryCatch(
    dbGetQuery(
      con,
      "SELECT 1
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = $1
         AND column_name = $2
       LIMIT 1",
      params = list(table, column)
    ),
    error = function(e) data.frame()
  )
  nrow(res) > 0
}

# Null-coalescing helper (base R gained %||% only in 4.4).
`%||%` <- function(a, b) if (is.null(a)) b else a

# Merge new rows into an existing selection, de-duplicated by id.
append_unique <- function(current, new_rows, id_column) {
  if (is.null(new_rows) || nrow(new_rows) == 0) return(current)
  if (is.null(current) || nrow(current) == 0) return(new_rows)
  combined <- rbind(current, new_rows)
  combined[!duplicated(combined[[id_column]]), , drop = FALSE]
}

# Convert 'HH:MM' / 'HH:MM:SS' text to seconds since midnight.
time_to_seconds <- function(t) {
  vapply(as.character(t), function(x) {
    if (is.na(x) || x == "") return(NA_real_)
    p <- suppressWarnings(as.integer(strsplit(x, ":")[[1]]))
    if (length(p) < 2 || any(is.na(p[1:2]))) return(NA_real_)
    s <- if (length(p) >= 3 && !is.na(p[3])) p[3] else 0
    p[1] * 3600 + p[2] * 60 + s
  }, numeric(1), USE.NAMES = FALSE)
}

seconds_to_hhmm <- function(x) {
  if (is.na(x)) return("—")
  x <- x %% (24 * 3600)
  sprintf("%02d:%02d", floor(x / 3600), floor((x %% 3600) / 60))
}

# Return readable descriptions of any overlapping performances
# (same day, overlapping start/end times).
find_conflicts <- function(df) {
  if (is.null(df) || nrow(df) < 2) return(character(0))
  
  start_s <- time_to_seconds(df$start_time)
  end_s   <- time_to_seconds(df$end_time)
  day     <- if ("day_name" %in% names(df)) df$day_name else rep("", nrow(df))
  
  out <- character(0)
  for (i in seq_len(nrow(df) - 1)) {
    for (j in (i + 1):nrow(df)) {
      ok <- !is.na(start_s[i]) && !is.na(end_s[i]) &&
        !is.na(start_s[j]) && !is.na(end_s[j]) &&
        identical(day[i], day[j])
      if (ok && start_s[i] < end_s[j] && start_s[j] < end_s[i]) {
        out <- c(out, sprintf(
          "%s and %s overlap on %s",
          df$artist_name[i], df$artist_name[j], day[i]
        ))
      }
    }
  }
  out
}

# A clean placeholder table for empty plan sections.
empty_plan_table <- function(message) {
  datatable(
    data.frame(Status = message),
    rownames = FALSE,
    options  = list(dom = "t", ordering = FALSE),
    class    = "compact"
  )
}

# Row-level Add/Remove buttons for the session plan.
row_plan_buttons <- function(ids, selected_ids, input_id, single = FALSE) {
  selected_ids <- as.character(selected_ids)
  
  vapply(ids, function(id) {
    id_chr <- as.character(id)
    is_selected <- id_chr %in% selected_ids
    
    if (single && is_selected) {
      return('<button class="btn-rowadd is-added" disabled>Selected</button>')
    }
    
    label <- if (is_selected) "Remove" else "Add"
    class_name <- if (is_selected) "btn-rowadd is-added" else "btn-rowadd"
    
    sprintf(
      "<button class=\"%s\" onclick=\"Shiny.setInputValue('%s','%s',{priority:'event'});\">%s</button>",
      class_name, input_id, id_chr, label
    )
  }, character(1), USE.NAMES = FALSE)
}

# Placeholder for an unavailable or empty section.
status_card <- function(icon, title, message) {
  div(
    class = "status-card",
    tags$i(class = paste("bi", icon), `aria-hidden` = "true"),
    h3(title),
    p(message)
  )
}

# ------------------------------------------------------------
# Theme
# ------------------------------------------------------------

app_theme <- bs_theme(
  version      = 5,
  bg           = "#F8F7F4",
  fg           = "#1C2541",
  primary      = "#24346B",
  secondary    = "#E15A3B",
  success      = "#2E9E7B",
  warning      = "#E0842F",
  danger       = "#C4462F",
  base_font    = font_google("Inter"),
  heading_font = font_google("Space Grotesk")
)

# ------------------------------------------------------------
# Reusable UI pieces
# ------------------------------------------------------------

fact_chip <- function(label) span(class = "fact-chip", label)


# ------------------------------------------------------------
# User interface
# ------------------------------------------------------------

ui <- page_navbar(
  id     = "main_nav",
  title  = span(class = "brand", span(class = "brand-dot"), "Bayfront Drift"),
  theme  = app_theme,
  fillable = FALSE,
  
  header = tags$head(
    useShinyjs(),
    # Bootstrap Icons font. bslib does NOT bundle it, so without this link
    # every bi-* icon (badge medallions, KPI chips, cost icons) renders empty.
    tags$link(
      rel = "stylesheet",
      href = "https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css"
    ),
    tags$link(rel = "stylesheet", type = "text/css", href = "styles.css?v=20260811-v4-5"),
    tags$script(HTML("
      window.copyPassportSummary = function() {
        const el = document.getElementById('passport_share_text');
        if (!el) {
          Shiny.setInputValue('passport_share_status', 'failed', {priority: 'event'});
          return;
        }

        const legacyCopy = function() {
          try {
            el.focus();
            el.select();
            el.setSelectionRange(0, el.value.length);
            const ok = document.execCommand('copy');
            Shiny.setInputValue(
              'passport_share_status',
              ok ? 'copied' : 'failed',
              {priority: 'event'}
            );
          } catch (err) {
            Shiny.setInputValue('passport_share_status', 'failed', {priority: 'event'});
          }
        };

        if (navigator.clipboard && window.isSecureContext) {
          navigator.clipboard.writeText(el.value)
            .then(function() {
              Shiny.setInputValue('passport_share_status', 'copied', {priority: 'event'});
            })
            .catch(legacyCopy);
        } else {
          legacyCopy();
        }
      };

      window.nativeSharePassport = function() {
        const el = document.getElementById('passport_share_text');
        if (!el) return;

        if (navigator.share) {
          navigator.share({
            title: 'My Bayfront Drift Passport',
            text: el.value
          }).then(function() {
            Shiny.setInputValue('passport_share_status', 'shared', {priority: 'event'});
          }).catch(function(err) {
            if (err && err.name === 'AbortError') return;
            Shiny.setInputValue('passport_share_status', 'native_unavailable', {priority: 'event'});
          });
        } else {
          Shiny.setInputValue('passport_share_status', 'native_unavailable', {priority: 'event'});
        }
      };
    "))
  ),
  
  # ---- HOME ----------------------------------------------
  nav_panel(
    "Home",
    value = "home",
    div(
      class = "page-wrap home-page",
      div(
        class = "hero",
        div(
          class = "hero-grid",
          div(
            class = "hero-copy",
            div(class = "hero-kicker", "SAN DIEGO · AUGUST 21–23, 2026"),
            h1("Plan your Bayfront festival weekend."),
            p(
              class = "hero-lead",
              "Build a personalized San Diego weekend around Waterfront Park — ",
              "from your festival pass and stay to food and free-time stops."
            ),
            div(
              class = "hero-actions",
              actionButton("go_plan", "Start planning", class = "btn-cta"),
              span(class = "hero-location",
                   tags$i(class = "bi bi-geo-alt-fill", `aria-hidden` = "true"),
                   " Waterfront Park · San Diego Bay")
            ),
            div(
              class = "hero-facts",
              fact_chip("Friday–Sunday"),
              fact_chip("3 festival stages"),
              fact_chip("Waterfront weekend")
            )
          ),
          div(
            class = "hero-weekend",
            div(class = "weekend-label", "WEEKEND AT A GLANCE"),
            div(
              class = "weekend-day",
              strong("Friday"),
              span("Aug 21"),
              tags$small("Festival Day 1 · Opening night")
            ),
            div(
              class = "weekend-day",
              strong("Saturday"),
              span("Aug 22"),
              tags$small("Festival Day 2 · Main festival day")
            ),
            div(
              class = "weekend-day",
              strong("Sunday"),
              span("Aug 23"),
              tags$small("Festival Day 3 · Finale")
            )
          )
        ),
        uiOutput("hero_metrics")
      ),
      div(
        class = "home-steps",
        div(class = "home-step",
            span(class = "home-step-num", "1"),
            h3("Choose your pass"),
            p("Pick your festival access and the exact day or days you want to attend.")),
        div(class = "home-step",
            span(class = "home-step-num", "2"),
            h3("Personalize the weekend"),
            p("Choose your hotel, restaurants, and San Diego free-time stops.")),
        div(class = "home-step",
            span(class = "home-step-num", "3"),
            h3("Review one complete plan"),
            p("See your estimated cost, travel guidance, schedule, and personal badges."))
      ),
      div(class = "home-footer",
          "Built with R Shiny and PostgreSQL.")
    )
  ),
  
  # ---- PLAN WEEKEND --------------------------------------
  nav_panel(
    "Plan weekend",
    value = "plan",
    div(
      class = "plan-wrap",
      navset_pill(
        id = "plan_step",
        
        # --- PASS ---
        nav_panel(
          "Pass",
          div(
            class = "page-content pass-page",
            h2(class = "section-title", "Choose your festival pass"),
            p(class = "section-note",
              "Choose GA or VIP for one, two, or all three festival days."),
            card(
              card_header("Festival passes"),
              DTOutput("ticket_table")
            ),
            uiOutput("ticket_day_selector"),
            div(
              class = "step-next",
              actionButton("next_stay", "Next: Stay", class = "btn-primary")
            )
          )
        ),
        
        # --- STAY ---
        nav_panel(
          "Stay",
          layout_sidebar(
            sidebar = sidebar(
              title = "Find a place to stay",
              textInput("lodging_search", "Search", placeholder = "Hotel or property name"),
              selectInput("lodging_price", "Price tier",
                          choices = "All", selected = "All"),
              sliderInput("lodging_rating", "Minimum rating",
                          min = 0, max = 5, value = 3, step = 0.5),
              sliderInput("lodging_distance", "Max distance from venue (km)",
                          min = 0, max = 25, value = 10, step = 0.5),
              actionButton("search_lodging", "Apply filters",
                           class = "btn-primary w-100"),
              p(class = "filter-hint", "Showing nearby options by default.")
            ),
            div(
              class = "page-content",
              uiOutput("stay_main"),
              div(
                class = "step-next",
                actionButton("next_food_from_stay", "Next: Food", class = "btn-primary")
              )
            )
          )
        ),
        
        # --- FOOD ---
        nav_panel(
          "Food",
          layout_sidebar(
            sidebar = sidebar(
              title = "Find food nearby",
              textInput("restaurant_search", "Search", placeholder = "Restaurant name"),
              selectInput("restaurant_cuisine", "Cuisine",
                          choices = "All", selected = "All"),
              selectInput("restaurant_price", "Price tier",
                          choices = "All", selected = "All"),
              sliderInput("restaurant_distance", "Max distance from venue (km)",
                          min = 0, max = 15, value = 5, step = 0.5),
              actionButton("search_restaurants", "Apply filters",
                           class = "btn-primary w-100"),
              p(class = "filter-hint", "Nearby restaurants load automatically.")
            ),
            div(
              class = "page-content",
              uiOutput("food_main"),
              div(
                class = "step-next",
                actionButton("next_freetime", "Next: Free time", class = "btn-primary")
              )
            )
          )
        ),
        
        # --- FREE TIME ---
        nav_panel(
          "Free time",
          layout_sidebar(
            sidebar = sidebar(
              title = "Explore San Diego",
              textInput("activity_search", "Search", placeholder = "Activity name"),
              selectInput("activity_type", "Activity type",
                          choices = "All", selected = "All"),
              selectInput("activity_price", "Price category",
                          choices = "All", selected = "All"),
              checkboxInput("activity_affordable", "Free or low-cost only",
                            value = FALSE),
              sliderInput("activity_max_price", "Max adult admission",
                          min = 0, max = 100, value = 100, step = 5, pre = "$"),
              actionButton("search_activities", "Apply filters",
                           class = "btn-primary w-100"),
              p(class = "filter-hint", "Activities load automatically.")
            ),
            div(
              class = "page-content",
              uiOutput("freetime_main"),
              div(
                class = "step-next",
                actionButton("next_myplan", "Next: My plan", class = "btn-primary")
              )
            )
          )
        )
      )
    )
  ),
  # ---- MY PASSPORT -----------------------------------------
  nav_panel(
    "My passport",
    value = "passport",
    div(
      class = "page-wrap passport-page",
      div(
        class = "passport-toolbar",
        div(
          span(class = "eyebrow", "YOUR FESTIVAL PROFILE"),
          h2(class = "section-title", "Bayfront Passport"),
          p(class = "section-note passport-note",
            "Every badge is earned from your plan.")
        ),
        uiOutput("passport_share_button")
      ),
      uiOutput("passport_content")
    )
  ),
  
  # ---- MY PLAN -------------------------------------------
  nav_panel(
    tagList("My plan", uiOutput("plan_badge", inline = TRUE)),
    value = "myplan",
    div(
      class = "page-wrap myplan-page",
      
      div(
        class = "myplan-heading",
        div(
          span(class = "eyebrow", "YOUR WEEKEND, IN ONE STORY"),
          h2(class = "section-title", "Your festival weekend"),
          p(class = "section-note",
            "A clear view of what you selected, what it costs, and how the weekend flows.")
        ),
        uiOutput("plan_ready_pill")
      ),
      
      uiOutput("plan_conflict_banner"),
      
      div(
        class = "stat-row stat-row-five",
        uiOutput("stat_ticket"),
        uiOutput("stat_total"),
        uiOutput("stat_lodging"),
        uiOutput("stat_restaurants"),
        uiOutput("stat_activities")
      ),
      
      div(
        class = "plan-actions",
        downloadButton("download_plan", "Download plan (CSV)", class = "btn-primary"),
        actionButton("clear_plan", "Clear plan", class = "btn-outline-danger")
      ),
      
      card(
        class = "cost-summary-card",
        card_header(
          div(
            strong("Cost breakdown"),
            span(class = "card-header-note", "Estimated from your selected pass, stays, meals, and activities")
          )
        ),
        uiOutput("budget_explanation")
      ),
      
      div(
        class = "story-section-head",
        span(class = "eyebrow", "DAY BY DAY"),
        h3("Your weekend story"),
        p("Each festival day connects your stay, trip to Waterfront Park, and festival schedule.")
      ),
      uiOutput("plan_story"),
      
      div(
        class = "story-section-head story-experience-head",
        span(class = "eyebrow", "BETWEEN THE SETS"),
        h3("Eat & explore"),
        p("The food and San Diego stops that make this weekend yours.")
      ),
      uiOutput("plan_experience_picks"),
      
      card(
        class = "festival-story-card",
        card_header(
          div(
            strong("Festival schedule"),
            span(class = "card-header-note", "Your pass already covers every performance on the selected day(s)")
          )
        ),
        tags$details(
          class = "story-details",
          tags$summary("View the festival schedule"),
          uiOutput("festival_schedule_overview")
        ),
        tags$details(
          class = "story-details",
          tags$summary("Customize my sets (optional)"),
          p(
            class = "small-note",
            "Save the sets you care about. Your suggested leave time will adapt to your earliest saved set for each day; if you save none, it uses the first scheduled festival set. Conflicts are flagged automatically."
          ),
          uiOutput("performance_picker"),
          uiOutput("plan_schedule")
        )
      )
    )
  )
)
# ------------------------------------------------------------
# Server
# ------------------------------------------------------------

server <- function(input, output, session) {
  
  # -- Connection --------------------------------------------
  con <- tryCatch(
    connect_to_db(),
    error = function(e) {
      showNotification(paste("Database connection failed:", e$message),
                       type = "error", duration = NULL)
      NULL
    }
  )
  
  session$onSessionEnded(function() {
    if (!is.null(con) && dbIsValid(con)) dbDisconnect(con)
  })
  
  db_ok <- function() !is.null(con) && dbIsValid(con)
  
  # Column presence checks (computed once per session).
  has_restaurant_source <- if (db_ok())
    column_exists(con, "restaurants", "source") else FALSE
  
  # Row counts drive empty-state behavior. Computed once and cached.
  counts <- reactive({
    list(
      accommodations = count_rows(con, "accommodations"),
      performances   = count_rows(con, "performances"),
      restaurants    = count_rows(con, "restaurants"),
      activities     = count_rows(con, "free_time_activities"),
      estimates      = count_rows(con, "accommodation_transit_estimates"),
      tickets        = count_rows(con, "ticket_options")
    )
  })
  
  # Session selections (kept only for this session).
  plan <- reactiveValues(
    ticket        = data.frame(),
    selected_days = character(0),
    lodging       = data.frame(),
    lodging_by_day = list(),
    performances  = data.frame(),
    restaurants   = data.frame(),
    activities    = data.frame()
  )
  
  
  # Populate filter choices from the database.
  observe({
    if (!db_ok()) return()
    
    distinct_vals <- function(sql) {
      res <- safe_query(con, sql)
      if (nrow(res) == 0) character(0) else res[[1]]
    }
    
    updateSelectInput(
      session, "lodging_price",
      choices = c(
        "All",
        distinct_vals(
          "SELECT DISTINCT price_tier
           FROM public.accommodations
           WHERE price_tier IS NOT NULL
             AND TRIM(price_tier) <> ''
           ORDER BY price_tier"
        )
      ),
      selected = "All"
    )
    
    lodging_max <- safe_query(
      con,
      "SELECT COALESCE(CEIL(MAX(distance_from_venue_km)), 25) AS m
       FROM public.accommodations",
      data.frame(m = 25)
    )
    
    updateSliderInput(
      session, "lodging_distance",
      max = max(5, lodging_max$m[1]),
      value = min(10, max(5, lodging_max$m[1]))
    )
    
    updateSelectInput(
      session, "restaurant_cuisine",
      choices = c(
        "All",
        distinct_vals(
          "SELECT DISTINCT cuisine_type
           FROM public.restaurants
           WHERE cuisine_type IS NOT NULL
             AND TRIM(cuisine_type) <> ''
           ORDER BY cuisine_type"
        )
      ),
      selected = "All"
    )
    
    updateSelectInput(
      session, "restaurant_price",
      choices = c(
        "All",
        distinct_vals(
          "SELECT DISTINCT price_tier
           FROM public.restaurants
           WHERE price_tier IS NOT NULL
             AND TRIM(price_tier) <> ''
           ORDER BY price_tier"
        )
      ),
      selected = "All"
    )
    
    rest_max <- safe_query(
      con,
      "SELECT COALESCE(CEIL(MAX(distance_from_venue_km)), 15) AS m
       FROM public.restaurants",
      data.frame(m = 15)
    )
    
    updateSliderInput(
      session, "restaurant_distance",
      max = max(5, rest_max$m[1]),
      value = min(5, max(5, rest_max$m[1]))
    )
    
    updateSelectInput(
      session, "activity_type",
      choices = c(
        "All",
        distinct_vals(
          "SELECT DISTINCT activity_type
           FROM public.free_time_activities
           WHERE activity_type IS NOT NULL
             AND TRIM(activity_type) <> ''
           ORDER BY activity_type"
        )
      ),
      selected = "All"
    )
    
    updateSelectInput(
      session, "activity_price",
      choices = c(
        "All",
        distinct_vals(
          "SELECT DISTINCT price_category
           FROM public.free_time_activities
           WHERE price_category IS NOT NULL
             AND TRIM(price_category) <> ''
           ORDER BY price_category"
        )
      ),
      selected = "All"
    )
    
    act_max <- safe_query(
      con,
      "SELECT COALESCE(CEIL(MAX(adult_price_usd)), 100) AS m
       FROM public.free_time_activities",
      data.frame(m = 100)
    )
    
    updateSliderInput(
      session, "activity_max_price",
      max = max(10, act_max$m[1]),
      value = max(10, act_max$m[1])
    )
  })
  
  # Disable search controls only if a source table is empty.
  observe({
    cts <- counts()
    toggleState("search_lodging", condition = cts$accommodations > 0)
    toggleState("search_restaurants", condition = cts$restaurants > 0)
    toggleState("search_activities", condition = cts$activities > 0)
  })
  
  # Hero KPI chips — database-driven, reusing the cached counts() reactive
  # so the same COUNT(*) results feed both the hero and the empty-state logic.
  output$hero_metrics <- renderUI({
    if (!db_ok()) return(NULL)
    cts <- counts()
    
    metric <- function(icon, value, label) {
      div(
        class = "hero-metric",
        tags$i(class = paste("bi", icon), `aria-hidden` = "true"),
        div(
          strong(value),
          span(label)
        )
      )
    }
    
    div(
      class = "hero-metrics",
      metric("bi-music-note-beamed", cts$performances, "Performances"),
      metric("bi-building", cts$accommodations, "Places to stay"),
      metric("bi-cup-hot", cts$restaurants, "Restaurants"),
      metric("bi-sun", cts$activities, "Free-time options")
    )
  })
  
  # Home CTA jumps to the planning tab.
  observeEvent(input$go_plan, {
    nav_select("main_nav", "plan", session = session)
  })
  
  
  # Guided planner navigation.
  observeEvent(input$next_stay, {
    if (nrow(plan$ticket) == 0 || length(plan$selected_days) != plan$ticket$days_covered[1]) {
      showNotification("Choose a pass and the matching festival day(s) first.",
                       type = "warning", duration = 3)
      return()
    }
    nav_select("plan_step", "Stay", session = session)
  })
  
  observeEvent(input$next_food_from_stay, {
    if (length(plan$selected_days) == 0) {
      showNotification(
        "Choose your festival pass and day(s) first.",
        type = "warning",
        duration = 3
      )
      return()
    }
    
    missing_days <- plan$selected_days[
      !vapply(
        plan$selected_days,
        function(day_id) {
          x <- plan$lodging_by_day[[as.character(day_id)]]
          !is.null(x) && nrow(x) > 0
        },
        logical(1)
      )
    ]
    
    if (length(missing_days) > 0) {
      day_names <- c("1" = "Friday", "2" = "Saturday", "3" = "Sunday")
      showNotification(
        paste0(
          "Assign accommodation for ",
          paste(unname(day_names[as.character(missing_days)]), collapse = " and "),
          " first."
        ),
        type = "warning",
        duration = 4
      )
      return()
    }
    
    nav_select("plan_step", "Food", session = session)
  })
  observeEvent(input$next_freetime, {
    nav_select("plan_step", "Free time", session = session)
  })
  observeEvent(input$next_myplan, {
    nav_select("main_nav", "myplan", session = session)
  })
  # A leaflet map with the venue marker always shown.
  base_map <- function(zoom = 12) {
    leaflet() |>
      addProviderTiles(providers$CartoDB.Positron) |>
      addCircles(lng = VENUE$lng, lat = VENUE$lat, radius = 1000,
                 color = "#24346B", weight = 1, opacity = 0.45,
                 fillColor = "#24346B", fillOpacity = 0.04,
                 group = "rings", label = "1 km from venue") |>
      addCircles(lng = VENUE$lng, lat = VENUE$lat, radius = 3000,
                 color = "#24346B", weight = 1, opacity = 0.28,
                 fill = FALSE, group = "rings", label = "3 km from venue") |>
      addAwesomeMarkers(
        lng = VENUE$lng, lat = VENUE$lat,
        icon = awesomeIcons(icon = "star", markerColor = "darkblue",
                            iconColor = "#FFFFFF", library = "fa"),
        label = paste0(VENUE$name, " (venue)")
      ) |>
      addControl(
        html = '<div class="map-legend"><b>Map</b><br>
                <span class="legend-dot venue-dot"></span> Festival venue<br>
                <span class="legend-dot option-dot"></span> Available option<br>
                <span class="legend-dot added-dot"></span> In My plan</div>',
        position = "bottomright"
      ) |>
      setView(lng = VENUE$lng, lat = VENUE$lat, zoom = zoom)
  }
  
  fit_or_center <- function(map, df) {
    if (nrow(df) == 0) return(map)
    map |> fitBounds(
      lng1 = min(df$longitude, VENUE$lng),
      lat1 = min(df$latitude,  VENUE$lat),
      lng2 = max(df$longitude, VENUE$lng),
      lat2 = max(df$latitude,  VENUE$lat)
    )
  }
  
  # Zoom to a marker selected from the map.
  focus_map_marker <- function(map_id, click, zoom = 15) {
    if (is.null(click) || is.null(click$lng) || is.null(click$lat)) return(invisible())
    leafletProxy(map_id) |>
      setView(lng = click$lng, lat = click$lat, zoom = zoom)
  }
  
  # Highlight the markers for the currently selected table rows.
  highlight_on_map <- function(map_id, res, sel) {
    proxy <- leafletProxy(map_id)
    clearGroup(proxy, "selected")
    if (length(sel) == 0 || is.null(res) || nrow(res) == 0) return(invisible())
    d <- res[sel, , drop = FALSE]
    d <- d[!is.na(d$latitude) & !is.na(d$longitude), , drop = FALSE]
    if (nrow(d) == 0) return(invisible())
    addCircleMarkers(proxy, data = d, lng = ~longitude, lat = ~latitude,
                     group = "selected", radius = 10, stroke = TRUE, color = "#24346B",
                     weight = 3, opacity = 1, fillColor = "#E15A3B", fillOpacity = 1)
  }
  
  # ==========================================================
  # PASS
  # ==========================================================
  
  ticket_data <- reactive({
    if (!db_ok() || counts()$tickets == 0) return(data.frame())
    safe_query(
      con,
      "SELECT ticket_id, ticket_type, days_covered, day_label, price, description
       FROM public.ticket_options
       ORDER BY ticket_type, days_covered"
    )
  })
  
  output$ticket_table <- renderDT({
    res <- ticket_data()
    validate(need(nrow(res) > 0, "No ticket options are currently available."))
    display <- res[, c("ticket_type", "day_label", "price", "description")]
    names(display) <- c("Access", "Pass", "Price", "Includes")
    display$Choose <- vapply(seq_len(nrow(res)), function(i) {
      selected <- nrow(plan$ticket) > 0 && as.character(res$ticket_id[i]) %in% as.character(plan$ticket$ticket_id)
      cls <- if (selected) "btn btn-sm btn-success plan-row-btn" else "btn btn-sm btn-primary plan-row-btn"
      label <- if (selected) "Selected" else "Choose"
      sprintf('<button class="%s" onclick="Shiny.setInputValue(\'choose_ticket\', \'%s\', {priority: \'event\'})">%s</button>', cls, res$ticket_id[i], label)
    }, character(1))
    datatable(display, rownames = FALSE, selection = "none", escape = FALSE,
              options = list(pageLength = 6, dom = "t", ordering = FALSE,
                             columnDefs = list(list(targets = ncol(display)-1, orderable = FALSE, className = "col-add"))),
              class = "stripe hover compact") |>
      formatCurrency("Price", "$", digits = 0)
  })
  
  observeEvent(input$choose_ticket, {
    res <- ticket_data()
    row <- res[as.character(res$ticket_id) == as.character(input$choose_ticket), , drop = FALSE]
    if (nrow(row) == 0) return()
    plan$ticket <- row[1, , drop = FALSE]
    plan$selected_days <- character(0)
    plan$performances <- data.frame()
    showNotification(paste0(row$day_label[1], " ", row$ticket_type[1], " pass selected."), type = "message", duration = 2)
  })
  
  day_combo_choices <- reactive({
    if (nrow(plan$ticket) == 0) return(character(0))
    n <- as.integer(plan$ticket$days_covered[1])
    if (n == 1) {
      c("Friday" = "1", "Saturday" = "2", "Sunday" = "3")
    } else if (n == 2) {
      c("Friday + Saturday" = "1,2", "Friday + Sunday" = "1,3", "Saturday + Sunday" = "2,3")
    } else {
      c("Friday + Saturday + Sunday" = "1,2,3")
    }
  })
  
  output$ticket_day_selector <- renderUI({
    if (nrow(plan$ticket) == 0) {
      return(div(class = "pass-selection-note",
                 tags$i(class = "bi bi-ticket-perforated", `aria-hidden` = "true"),
                 span("Choose a pass above to select your festival day(s).")))
    }
    choices <- day_combo_choices()
    selected_value <- if (length(plan$selected_days) > 0) paste(plan$selected_days, collapse = ",") else if (length(choices)==1) unname(choices[1]) else ""
    tagList(
      div(class = "pass-selected-summary",
          div(span(class = "eyebrow", "Selected pass"),
              h3(paste(plan$ticket$day_label[1], plan$ticket$ticket_type[1])),
              p(plan$ticket$description[1])),
          div(class = "pass-price", span("Price"), strong(paste0("$", formatC(plan$ticket$price[1], format = "f", digits = 0))))),
      selectInput("festival_day_combo", "Festival day(s)", choices = c("Choose day(s)" = "", choices), selected = selected_value)
    )
  })
  
  observeEvent(input$festival_day_combo, {
    if (is.null(input$festival_day_combo) || input$festival_day_combo == "") {
      plan$selected_days <- character(0)
      return()
    }
    days <- strsplit(input$festival_day_combo, ",", fixed = TRUE)[[1]]
    plan$selected_days <- days
    if (nrow(plan$performances) > 0) {
      plan$performances <- plan$performances[as.character(plan$performances$day_id) %in% days, , drop = FALSE]
    }
  }, ignoreInit = TRUE)
  
  observe({
    if (nrow(plan$ticket) == 0) return()
    choices <- day_combo_choices()
    if (length(choices) == 1 && length(plan$selected_days) == 0) {
      plan$selected_days <- strsplit(unname(choices[1]), ",", fixed = TRUE)[[1]]
    }
  })
  
  # ==========================================================
  # STAY
  # ==========================================================
  
  lodging_data <- eventReactive(input$search_lodging, {
    if (!db_ok()) return(data.frame())
    sql <- DBI::sqlInterpolate(con,
                               "SELECT lodging_id, name, property_type, rating_5, price_tier,
              num_reviews, distance_from_venue_km, address, source,
              latitude, longitude, price_per_night
       FROM public.accommodations
       WHERE (?search = '' OR LOWER(name) LIKE LOWER(?pattern))
         AND (?price = 'All' OR price_tier = ?price)
         AND COALESCE(rating_5, 0) >= ?rating
         AND COALESCE(distance_from_venue_km, 9999) <= ?distance
       ORDER BY distance_from_venue_km, rating_5 DESC, name
       LIMIT 200",
                               search = trimws(input$lodging_search),
                               pattern = paste0("%", trimws(input$lodging_search), "%"),
                               price = input$lodging_price,
                               rating = input$lodging_rating,
                               distance = input$lodging_distance)
    safe_query(con, sql)
  }, ignoreInit = FALSE, ignoreNULL = FALSE)
  
  output$stay_main <- renderUI({
    if (counts()$accommodations == 0) {
      return(status_card("bi-buildings",
                         "Accommodations unavailable",
                         "No accommodation data is currently available."))
    }
    tagList(
      h2(class = "section-title", "Choose where to stay"),
      p(class = "section-note",
        "Assign a hotel to each festival day, or use the same hotel for your full stay."),
      div(
        class = "planner-stack",
        card(
          full_screen = TRUE,
          card_header("Map"),
          leafletOutput("lodging_map", height = 390)
        ),
        card(
          full_screen = TRUE,
          card_header("Results"),
          DTOutput("lodging_table")
        ),
        card(
          class = "stay-assignment-section",
          card_header("Your stay by festival day"),
          uiOutput("lodging_assignment")
        )
      )
    )
  })
  
  output$lodging_table <- renderDT({
    res <- lodging_data()
    validate(need(nrow(res) > 0, "No accommodations match your filters."))
    display <- res[, c("name", "property_type", "rating_5",
                       "price_per_night", "distance_from_venue_km")]
    names(display) <- c("Name", "Property type", "Rating",
                        "Price / night", "Distance (km)")
    assigned_ids <- vapply(
      plan$lodging_by_day,
      function(x) {
        if (is.null(x) || nrow(x) == 0) NA_character_ else as.character(x$lodging_id[1])
      },
      character(1)
    )
    
    display$Add <- vapply(seq_len(nrow(res)), function(i) {
      assigned <- as.character(res$lodging_id[i]) %in% assigned_ids
      cls <- if (assigned) {
        "btn btn-sm btn-success plan-row-btn"
      } else {
        "btn btn-sm btn-primary plan-row-btn"
      }
      label <- if (assigned) "Assigned" else "Choose"
      
      sprintf(
        '<button class="%s" onclick="Shiny.setInputValue(\'choose_lodging_row\', \'%s\', {priority: \'event\'})">%s</button>',
        cls,
        res$lodging_id[i],
        label
      )
    }, character(1))
    datatable(display, rownames = FALSE, selection = "single", escape = FALSE,
              options = list(pageLength = 14, dom = "tp",
                             columnDefs = list(list(targets = ncol(display) - 1,
                                                    orderable = FALSE, className = "col-add"))),
              class = "stripe hover compact") |>
      formatRound("Rating", 1) |>
      formatCurrency("Price / night", "$", digits = 0) |>
      formatRound("Distance (km)", 2)
  })
  
  
  sync_lodging_summary <- function() {
    assigned <- lapply(plan$selected_days, function(day_id) {
      x <- plan$lodging_by_day[[as.character(day_id)]]
      if (is.null(x) || nrow(x) == 0) return(NULL)
      y <- x[1, , drop = FALSE]
      y$assigned_day_id <- as.integer(day_id)
      y
    })
    assigned <- assigned[!vapply(assigned, is.null, logical(1))]
    plan$lodging <- if (length(assigned) == 0) data.frame() else do.call(rbind, assigned)
  }
  
  output$lodging_assignment <- renderUI({
    if (length(plan$selected_days) == 0) {
      return(status_card(
        "bi-calendar3",
        "Choose festival days first",
        "Select your pass and festival day(s) before assigning accommodation."
      ))
    }
    
    day_names <- c("1" = "Friday", "2" = "Saturday", "3" = "Sunday")
    
    rows <- lapply(plan$selected_days, function(day_id) {
      assigned <- plan$lodging_by_day[[as.character(day_id)]]
      
      if (is.null(assigned) || nrow(assigned) == 0) {
        div(
          class = "stay-day-row",
          div(
            span(class = "eyebrow", unname(day_names[as.character(day_id)])),
            strong("No hotel assigned")
          ),
          span(class = "stay-day-price", "—")
        )
      } else {
        div(
          class = "stay-day-row",
          div(
            span(class = "eyebrow", unname(day_names[as.character(day_id)])),
            strong(assigned$name[1]),
            span(
              paste0(
                assigned$property_type[1], " · $",
                formatC(assigned$price_per_night[1], format = "f", digits = 0),
                "/night"
              )
            )
          ),
          actionButton(
            paste0("remove_lodging_", day_id),
            "Remove",
            class = "btn btn-sm btn-outline-danger"
          )
        )
      }
    })
    
    tagList(
      div(class = "stay-assignment-card", rows),
      uiOutput("lodging_choice_panel")
    )
  })
  
  output$lodging_choice_panel <- renderUI({
    req(input$choose_lodging_row)
    res <- lodging_data()
    row <- res[as.character(res$lodging_id) == as.character(input$choose_lodging_row), , drop = FALSE]
    if (nrow(row) == 0 || length(plan$selected_days) == 0) return(NULL)
    
    day_names <- c("1" = "Friday", "2" = "Saturday", "3" = "Sunday")
    choices <- setNames(as.character(plan$selected_days), unname(day_names[as.character(plan$selected_days)]))
    
    div(
      class = "lodging-choice-panel",
      h4(paste0("Assign ", row$name[1])),
      selectInput(
        "lodging_assign_day",
        "Assign to",
        choices = choices,
        selected = as.character(plan$selected_days[1])
      ),
      checkboxInput(
        "lodging_use_all_days",
        "Use this hotel for all selected festival days",
        value = FALSE
      ),
      actionButton(
        "confirm_lodging_assignment",
        "Assign stay",
        class = "btn-primary"
      )
    )
  })
  
  observeEvent(input$confirm_lodging_assignment, {
    req(input$choose_lodging_row)
    res <- lodging_data()
    row <- res[as.character(res$lodging_id) == as.character(input$choose_lodging_row), , drop = FALSE]
    if (nrow(row) == 0) return()
    
    if (isTRUE(input$lodging_use_all_days)) {
      for (day_id in plan$selected_days) {
        plan$lodging_by_day[[as.character(day_id)]] <- row[1, , drop = FALSE]
      }
    } else {
      req(input$lodging_assign_day)
      plan$lodging_by_day[[as.character(input$lodging_assign_day)]] <- row[1, , drop = FALSE]
    }
    
    sync_lodging_summary()
    
    showNotification("Accommodation assignment updated.", type = "message", duration = 2)
  })
  
  for (day_id in c("1", "2", "3")) {
    local({
      d <- day_id
      observeEvent(input[[paste0("remove_lodging_", d)]], {
        plan$lodging_by_day[[d]] <- NULL
        sync_lodging_summary()
      })
    })
  }
  
  output$lodging_map <- renderLeaflet({
    res <- lodging_data()
    mapped <- res[!is.na(res$latitude) & !is.na(res$longitude), , drop = FALSE]
    mapped$marker_color <- ifelse(
      as.character(mapped$lodging_id) %in%
        vapply(
          plan$lodging_by_day,
          function(x) if (is.null(x) || nrow(x) == 0) NA_character_ else as.character(x$lodging_id[1]),
          character(1)
        ),
      "#2E9E7B", "#E15A3B"
    )
    m <- base_map(13)
    if (nrow(mapped) == 0) return(m)
    m |>
      addCircleMarkers(data = mapped, lng = ~longitude, lat = ~latitude,
                       layerId = ~as.character(lodging_id),
                       radius = 5, stroke = FALSE, fillOpacity = 0.8, fillColor = ~marker_color,
                       label = ~paste0(name, " · $",
                                       formatC(price_per_night, format = "f", digits = 0),
                                       "/night · ", round(distance_from_venue_km, 2), " km from venue")) |>
      fit_or_center(mapped)
  })
  observeEvent(input$lodging_table_rows_selected, {
    res <- tryCatch(lodging_data(), error = function(e) data.frame())
    highlight_on_map("lodging_map", res, input$lodging_table_rows_selected)
  }, ignoreNULL = FALSE, ignoreInit = TRUE)
  
  observeEvent(input$lodging_map_marker_click, {
    click <- input$lodging_map_marker_click
    id <- click$id
    if (is.null(id)) return()
    
    res <- lodging_data()
    row_index <- match(as.character(id), as.character(res$lodging_id))
    if (is.na(row_index)) return()
    
    proxy <- dataTableProxy("lodging_table")
    selectRows(proxy, row_index)
    selectPage(proxy, ceiling(row_index / 14))
    focus_map_marker("lodging_map", click, zoom = 16)
  })
  
  # ==========================================================
  # PERFORMANCES
  # ==========================================================
  
  performance_options <- reactive({
    if (!db_ok() || counts()$performances == 0 || length(plan$selected_days) == 0) {
      return(data.frame())
    }
    
    res <- safe_query(
      con,
      "SELECT
         p.performance_id,
         p.artist_name,
         p.genre,
         p.day_id,
         d.day_name,
         d.day_date,
         p.stage_id,
         s.stage_name,
         p.start_time,
         p.end_time
       FROM public.performances p
       JOIN public.festival_days d
         ON p.day_id = d.day_id
       JOIN public.stages s
         ON p.stage_id = s.stage_id
       ORDER BY p.day_id, p.start_time, s.stage_name, p.artist_name"
    )
    
    if (nrow(res) == 0) return(res)
    res[as.character(res$day_id) %in% as.character(plan$selected_days), , drop = FALSE]
  })
  
  output$performance_picker <- renderUI({
    if (nrow(plan$ticket) == 0 || length(plan$selected_days) == 0) {
      return(status_card(
        "bi-ticket-perforated",
        "Choose your pass first",
        "Select a festival pass and day(s) to view the lineup."
      ))
    }
    
    res <- performance_options()
    if (nrow(res) == 0) {
      return(status_card(
        "bi-music-note-beamed",
        "No performances available",
        "No performances were found for the selected festival day(s)."
      ))
    }
    
    day_names <- unique(res$day_name)
    
    cards <- lapply(day_names, function(day_nm) {
      day_res <- res[res$day_name == day_nm, , drop = FALSE]
      
      choices <- setNames(
        as.character(day_res$performance_id),
        paste0(
          day_res$artist_name, " · ",
          day_res$stage_name, " · ",
          substr(as.character(day_res$start_time), 1, 5)
        )
      )
      
      selected_ids <- if (nrow(plan$performances) == 0) character(0) else {
        as.character(
          plan$performances$performance_id[
            as.character(plan$performances$day_id) ==
              as.character(day_res$day_id[1])
          ]
        )
      }
      
      div(
        class = "performance-day-card",
        div(
          class = "performance-day-head",
          h3(day_nm),
          span(paste0(nrow(day_res), " sets"))
        ),
        checkboxGroupInput(
          inputId = paste0("performance_day_", day_res$day_id[1]),
          label = NULL,
          choices = choices,
          selected = selected_ids
        )
      )
    })
    
    tagList(
      div(class = "performance-picker-grid", cards),
      p(
        class = "small-note",
        "Saved as your personal schedule. Time conflicts are flagged automatically."
      )
    )
  })
  
  observe({
    res <- performance_options()
    if (nrow(res) == 0 || length(plan$selected_days) == 0) {
      plan$performances <- data.frame()
      return()
    }
    
    selected_ids <- character(0)
    for (day_id in unique(as.character(res$day_id))) {
      value <- input[[paste0("performance_day_", day_id)]]
      if (!is.null(value)) selected_ids <- c(selected_ids, as.character(value))
    }
    
    selected_ids <- unique(selected_ids)
    if (length(selected_ids) == 0) {
      plan$performances <- data.frame()
    } else {
      plan$performances <- res[
        as.character(res$performance_id) %in% selected_ids,
        , drop = FALSE
      ]
    }
  })
  
  # ==========================================================
  # FOOD
  # ==========================================================
  
  restaurant_data <- eventReactive(input$search_restaurants, {
    if (!db_ok()) return(data.frame())
    # Restaurant source field compatibility.
    src_expr <- if (has_restaurant_source) "source" else "NULL::text"
    template <- sprintf(
      "SELECT restaurant_id, restaurant_name, cuisine_type, rating,
              review_count, price_tier, area, distance_from_venue_km,
              address, %s AS source, latitude, longitude, price_per_meal
       FROM public.restaurants
       WHERE (?search = '' OR LOWER(restaurant_name) LIKE LOWER(?pattern))
         AND (?cuisine = 'All' OR cuisine_type = ?cuisine)
         AND (?price = 'All'   OR price_tier = ?price)
         AND COALESCE(distance_from_venue_km, 9999) <= ?distance
       ORDER BY distance_from_venue_km, rating DESC, restaurant_name
       LIMIT 200", src_expr)
    sql <- DBI::sqlInterpolate(con, template,
                               search = trimws(input$restaurant_search),
                               pattern = paste0("%", trimws(input$restaurant_search), "%"),
                               cuisine = input$restaurant_cuisine,
                               price = input$restaurant_price,
                               distance = input$restaurant_distance)
    safe_query(con, sql)
  }, ignoreInit = FALSE, ignoreNULL = FALSE)
  
  output$food_main <- renderUI({
    if (counts()$restaurants == 0) {
      return(status_card(
        "bi-cup-hot",
        "Restaurants unavailable",
        "No restaurant data is currently available."
      ))
    }
    tagList(
      h2(class = "section-title", "Plan meals around the music"),
      p(class = "section-note",
        "Compare cuisine, estimated meal price, rating, area, and distance."),
      div(
        class = "planner-stack",
        card(
          full_screen = TRUE,
          card_header("Map"),
          leafletOutput("restaurant_map", height = 390)
        ),
        card(
          full_screen = TRUE,
          card_header("Results"),
          DTOutput("restaurant_table")
        )
      )
    )
  })
  
  output$restaurant_table <- renderDT({
    res <- restaurant_data()
    validate(need(nrow(res) > 0, "No restaurants match your filters."))
    display <- res[, c("restaurant_name", "cuisine_type", "rating",
                       "price_per_meal", "area", "distance_from_venue_km")]
    names(display) <- c("Restaurant", "Cuisine", "Rating",
                        "Price / meal", "Area", "Distance (km)")
    display$Add <- row_plan_buttons(res$restaurant_id, plan$restaurants$restaurant_id, "add_one_restaurant")
    datatable(display, rownames = FALSE, selection = "multiple", escape = FALSE,
              options = list(pageLength = 12, dom = "tp",
                             columnDefs = list(list(targets = ncol(display) - 1,
                                                    orderable = FALSE, className = "col-add"))),
              class = "stripe hover compact") |>
      formatRound("Rating", 1) |>
      formatCurrency("Price / meal", "$", digits = 0) |>
      formatRound("Distance (km)", 2)
  })
  
  output$restaurant_map <- renderLeaflet({
    res <- restaurant_data()
    mapped <- res[!is.na(res$latitude) & !is.na(res$longitude), , drop = FALSE]
    mapped$marker_color <- ifelse(
      as.character(mapped$restaurant_id) %in% as.character(plan$restaurants$restaurant_id),
      "#2E9E7B", "#E15A3B"
    )
    m <- base_map(13)
    if (nrow(mapped) == 0) return(m)
    m |>
      addCircleMarkers(data = mapped, lng = ~longitude, lat = ~latitude,
                       layerId = ~as.character(restaurant_id),
                       radius = 5, stroke = FALSE, fillOpacity = 0.8, fillColor = ~marker_color,
                       label = ~paste0(restaurant_name, " · ", cuisine_type, " · $",
                                       formatC(price_per_meal, format = "f", digits = 0), "/meal")) |>
      fit_or_center(mapped)
  })
  
  
  observeEvent(input$add_one_restaurant, {
    res <- restaurant_data()
    row <- res[as.character(res$restaurant_id) == input$add_one_restaurant, , drop = FALSE]
    if (nrow(row) == 0) return()
    
    current <- plan$restaurants
    already_added <- nrow(current) > 0 &&
      as.character(row$restaurant_id[1]) %in% as.character(current$restaurant_id)
    
    if (already_added) {
      plan$restaurants <- current[
        as.character(current$restaurant_id) != as.character(row$restaurant_id[1]),
        , drop = FALSE
      ]
      showNotification(paste(row$restaurant_name[1], "removed from your plan."),
                       type = "message", duration = 2)
    } else {
      plan$restaurants <- append_unique(
        current, row[1, , drop = FALSE], "restaurant_id"
      )
      
      showNotification(paste(row$restaurant_name[1], "added to your plan."), type = "message", duration = 2)
    }
  })
  
  observeEvent(input$restaurant_table_rows_selected, {
    res <- tryCatch(restaurant_data(), error = function(e) data.frame())
    highlight_on_map("restaurant_map", res, input$restaurant_table_rows_selected)
  }, ignoreNULL = FALSE, ignoreInit = TRUE)
  
  observeEvent(input$restaurant_map_marker_click, {
    click <- input$restaurant_map_marker_click
    id <- click$id
    if (is.null(id)) return()
    
    res <- restaurant_data()
    row_index <- match(as.character(id), as.character(res$restaurant_id))
    if (is.na(row_index)) return()
    
    proxy <- dataTableProxy("restaurant_table")
    selectRows(proxy, row_index)
    selectPage(proxy, ceiling(row_index / 12))
    focus_map_marker("restaurant_map", click, zoom = 16)
  })
  
  # ==========================================================
  # FREE TIME
  # ==========================================================
  
  activity_data <- eventReactive(input$search_activities, {
    if (!db_ok()) return(data.frame())
    sql <- DBI::sqlInterpolate(con,
                               "SELECT activity_id, activity_name, activity_type, activity_location,
              operating_hours, adult_price_usd, price_category,
              is_free_or_low_cost, description, price_notes,
              primary_source, verified_date, latitude, longitude
       FROM public.free_time_activities
       WHERE (?search = '' OR LOWER(activity_name) LIKE LOWER(?pattern))
         AND (?atype = 'All' OR activity_type = ?atype)
         AND (?pcat = 'All'  OR price_category = ?pcat)
         AND (?afford = FALSE OR is_free_or_low_cost = TRUE)
         AND COALESCE(adult_price_usd, 0) <= ?maxp
       ORDER BY adult_price_usd, activity_name",
                               search = trimws(input$activity_search),
                               pattern = paste0("%", trimws(input$activity_search), "%"),
                               atype = input$activity_type,
                               pcat = input$activity_price,
                               afford = input$activity_affordable,
                               maxp = input$activity_max_price)
    safe_query(con, sql)
  }, ignoreInit = FALSE, ignoreNULL = FALSE)
  
  output$freetime_main <- renderUI({
    if (counts()$activities == 0) {
      return(status_card("bi-compass",
                         "Activities unavailable",
                         "No free-time activity data is currently available."))
    }
    tagList(
      h2(class = "section-title", "Use free time to experience the city"),
      p(class = "section-note",
        "Filter by type and price, or show only free and low-cost options."),
      div(
        class = "planner-stack",
        card(
          full_screen = TRUE,
          card_header("Map"),
          leafletOutput("activity_map", height = 410)
        ),
        card(
          full_screen = TRUE,
          card_header("Results"),
          DTOutput("activity_table")
        )
      )
    )
  })
  
  output$activity_table <- renderDT({
    res <- activity_data()
    validate(need(nrow(res) > 0, "No activities match your filters."))
    display <- res[, c("activity_name", "activity_type", "activity_location",
                       "adult_price_usd", "is_free_or_low_cost")]
    display$is_free_or_low_cost <- ifelse(display$is_free_or_low_cost, "Yes", "No")
    names(display) <- c("Activity", "Type", "Location",
                        "Adult price", "Free / low-cost")
    display$Add <- row_plan_buttons(res$activity_id, plan$activities$activity_id, "add_one_activity")
    datatable(display, rownames = FALSE, selection = "multiple", escape = FALSE,
              options = list(pageLength = 12, dom = "tp",
                             columnDefs = list(
                               list(targets = 2, width = "220px"),
                               list(targets = ncol(display) - 1, orderable = FALSE, className = "col-add"))),
              class = "stripe hover compact") |>
      formatCurrency("Adult price", "$", digits = 2)
  })
  
  output$activity_map <- renderLeaflet({
    res <- activity_data()
    mapped <- res[!is.na(res$latitude) & !is.na(res$longitude), , drop = FALSE]
    mapped$marker_color <- ifelse(
      as.character(mapped$activity_id) %in% as.character(plan$activities$activity_id),
      "#2E9E7B", "#E15A3B"
    )
    m <- base_map(11)
    if (nrow(mapped) == 0) return(m)
    m |>
      addCircleMarkers(data = mapped, lng = ~longitude, lat = ~latitude,
                       layerId = ~as.character(activity_id),
                       radius = 6, stroke = FALSE, fillOpacity = 0.85, fillColor = ~marker_color,
                       label = ~paste0(activity_name, " · ", price_category, " · $",
                                       formatC(adult_price_usd, format = "f", digits = 2))) |>
      fit_or_center(mapped)
  })
  
  
  observeEvent(input$add_one_activity, {
    res <- activity_data()
    row <- res[as.character(res$activity_id) == input$add_one_activity, , drop = FALSE]
    if (nrow(row) == 0) return()
    
    current <- plan$activities
    already_added <- nrow(current) > 0 &&
      as.character(row$activity_id[1]) %in% as.character(current$activity_id)
    
    if (already_added) {
      plan$activities <- current[
        as.character(current$activity_id) != as.character(row$activity_id[1]),
        , drop = FALSE
      ]
      showNotification(paste(row$activity_name[1], "removed from your plan."),
                       type = "message", duration = 2)
    } else {
      plan$activities <- append_unique(
        current, row[1, , drop = FALSE], "activity_id"
      )
      
      showNotification(paste(row$activity_name[1], "added to your plan."), type = "message", duration = 2)
    }
  })
  
  observeEvent(input$activity_table_rows_selected, {
    res <- tryCatch(activity_data(), error = function(e) data.frame())
    highlight_on_map("activity_map", res, input$activity_table_rows_selected)
  }, ignoreNULL = FALSE, ignoreInit = TRUE)
  
  observeEvent(input$activity_map_marker_click, {
    click <- input$activity_map_marker_click
    id <- click$id
    if (is.null(id)) return()
    
    res <- activity_data()
    row_index <- match(as.character(id), as.character(res$activity_id))
    if (is.na(row_index)) return()
    
    proxy <- dataTableProxy("activity_table")
    selectRows(proxy, row_index)
    selectPage(proxy, ceiling(row_index / 12))
    focus_map_marker("activity_map", click, zoom = 15)
  })
  
  # ==========================================================
  # GETTING AROUND
  # ==========================================================
  
  # Travel estimates for the selected accommodation.
  recommended_transit <- reactive({
    if (!db_ok() || length(plan$selected_days) == 0 || length(plan$lodging_by_day) == 0) {
      return(data.frame())
    }
    
    rows <- lapply(plan$selected_days, function(day_id) {
      stay <- plan$lodging_by_day[[as.character(day_id)]]
      if (is.null(stay) || nrow(stay) == 0) return(NULL)
      
      sql <- DBI::sqlInterpolate(
        con,
        "SELECT
           e.lodging_id,
           a.name AS accommodation_name,
           e.day_id,
           d.day_name,
           e.mode,
           e.estimated_minutes,
           e.departure_time,
           e.num_stops,
           e.origin_stop,
           e.destination_stop,
           e.trip_id
         FROM public.accommodation_transit_estimates e
         JOIN public.accommodations a
           ON e.lodging_id = a.lodging_id
         JOIN public.festival_days d
           ON e.day_id = d.day_id
         WHERE e.lodging_id = ?lid
           AND e.day_id = ?day_id
         LIMIT 1",
        lid = as.integer(stay$lodging_id[1]),
        day_id = as.integer(day_id)
      )
      
      res <- safe_query(con, sql)
      if (nrow(res) > 0) {
        res$estimate_source <- "Database travel estimate"
        return(res[1, , drop = FALSE])
      }
      
      distance_km <- suppressWarnings(as.numeric(stay$distance_from_venue_km[1]))
      walk_minutes <- if (is.na(distance_km)) {
        NA_real_
      } else {
        round(distance_km * 12, 1)
      }
      
      data.frame(
        lodging_id = stay$lodging_id[1],
        accommodation_name = stay$name[1],
        day_id = as.integer(day_id),
        day_name = c("Friday", "Saturday", "Sunday")[as.integer(day_id)],
        mode = ifelse(is.na(walk_minutes), "Estimate unavailable", "Walk"),
        estimated_minutes = walk_minutes,
        departure_time = NA_character_,
        num_stops = 0L,
        origin_stop = stay$name[1],
        destination_stop = "Waterfront Park",
        trip_id = NA_character_,
        estimate_source = ifelse(
          is.na(walk_minutes),
          "No estimate available",
          "Distance-based walking estimate"
        ),
        stringsAsFactors = FALSE
      )
    })
    
    rows <- rows[!vapply(rows, is.null, logical(1))]
    if (length(rows) == 0) return(data.frame())
    do.call(rbind, rows)
  })
  
  
  selected_performances_for_day <- function(day_id) {
    if (nrow(plan$performances) == 0) return("")
    rows <- plan$performances[
      as.character(plan$performances$day_id) == as.character(day_id),
      , drop = FALSE
    ]
    if (nrow(rows) == 0) return("")
    paste0(
      rows$artist_name, " · ", rows$stage_name, " · ",
      substr(as.character(rows$start_time), 1, 5),
      collapse = " | "
    )
  }
  
  first_festival_performance_for_day <- function(day_id) {
    if (!db_ok()) return(NULL)
    sql <- DBI::sqlInterpolate(
      con,
      "SELECT
         p.performance_id,
         p.artist_name,
         p.start_time,
         s.stage_name,
         d.day_date
       FROM public.performances p
       JOIN public.stages s
         ON p.stage_id = s.stage_id
       JOIN public.festival_days d
         ON p.day_id = d.day_id
       WHERE p.day_id = ?day_id
       ORDER BY p.start_time, p.stage_id, p.performance_id
       LIMIT 1",
      day_id = as.integer(day_id)
    )
    res <- safe_query(con, sql)
    if (nrow(res) == 0) return(NULL)
    res$target_type <- "festival_opening"
    res[1, , drop = FALSE]
  }
  
  festival_day_date <- function(day_id) {
    if (!db_ok()) return(NA_character_)
    sql <- DBI::sqlInterpolate(
      con,
      "SELECT day_date
       FROM public.festival_days
       WHERE day_id = ?day_id
       LIMIT 1",
      day_id = as.integer(day_id)
    )
    res <- safe_query(con, sql)
    if (nrow(res) == 0 || is.na(res$day_date[1])) return(NA_character_)
    as.character(res$day_date[1])
  }
  
  # The attendee's earliest saved set drives arrival for that day.
  # If no sets are saved for the day, use the first scheduled set.
  departure_target_for_day <- function(day_id) {
    if (nrow(plan$performances) > 0) {
      selected <- plan$performances[
        as.character(plan$performances$day_id) == as.character(day_id),
        , drop = FALSE
      ]
      
      if (nrow(selected) > 0) {
        starts <- time_to_seconds(selected$start_time)
        valid <- which(!is.na(starts))
        
        if (length(valid) > 0) {
          idx <- valid[which.min(starts[valid])]
          target <- selected[idx, , drop = FALSE]
          target$day_date <- festival_day_date(day_id)
          target$target_type <- "selected_set"
          return(target)
        }
      }
    }
    
    first_festival_performance_for_day(day_id)
  }
  
  suggested_departure_for_day <- function(day_id, travel_minutes, fallback_departure = NA) {
    target <- departure_target_for_day(day_id)
    
    if (
      !is.null(target) &&
      nrow(target) > 0 &&
      !is.na(travel_minutes) &&
      "day_date" %in% names(target) &&
      !is.na(target$day_date[1])
    ) {
      start_txt <- substr(as.character(target$start_time[1]), 1, 8)
      day_txt <- as.character(target$day_date[1])
      
      start_time <- as.POSIXct(
        paste(day_txt, start_txt),
        format = "%Y-%m-%d %H:%M:%S"
      )
      
      arrival_buffer_minutes <- 60
      leave_time <- start_time - (as.numeric(travel_minutes) + arrival_buffer_minutes) * 60
      
      target_type <- if (
        "target_type" %in% names(target) &&
        identical(as.character(target$target_type[1]), "selected_set")
      ) {
        "selected_set"
      } else {
        "festival_opening"
      }
      
      basis_prefix <- if (target_type == "selected_set") {
        "First selected set"
      } else {
        "First scheduled set"
      }
      
      return(list(
        time = format(leave_time, "%H:%M"),
        basis = paste0(
          basis_prefix, ": ",
          target$artist_name[1], " · ",
          target$stage_name[1], " · ",
          substr(as.character(target$start_time[1]), 1, 5)
        ),
        target_type = target_type,
        target_artist = as.character(target$artist_name[1]),
        target_stage = as.character(target$stage_name[1]),
        target_time = substr(as.character(target$start_time[1]), 1, 5),
        buffer_minutes = arrival_buffer_minutes
      ))
    }
    
    fallback <- as.character(fallback_departure)
    if (!is.na(fallback) && nchar(fallback) >= 5) {
      return(list(
        time = substr(fallback, 1, 5),
        basis = "Database departure reference",
        target_type = "database_reference",
        target_artist = "",
        target_stage = "",
        target_time = "",
        buffer_minutes = NA_integer_
      ))
    }
    
    list(
      time = "—",
      basis = "No departure estimate available",
      target_type = "unavailable",
      target_artist = "",
      target_stage = "",
      target_time = "",
      buffer_minutes = NA_integer_
    )
  }
  
  
  # ==========================================================
  # MY PASSPORT
  # ==========================================================
  
  passport_modal_step <- reactiveVal("Pass")
  
  passport_model <- reactive({
    day_names <- c("1" = "Friday", "2" = "Saturday", "3" = "Sunday")
    selected_days <- as.character(plan$selected_days)
    badges <- list()
    
    add_badge <- function(
    id, title, subtitle, icon, tone,
    kicker, detail_type, planner_step
    ) {
      badges[[length(badges) + 1]] <<- list(
        id = id,
        title = title,
        subtitle = subtitle,
        icon = icon,
        tone = tone,
        kicker = kicker,
        detail_type = detail_type,
        planner_step = planner_step
      )
    }
    
    # Festival access - direct from ticket_options + selected days.
    if (nrow(plan$ticket) > 0) {
      selected_label <- paste(unname(day_names[selected_days]), collapse = " + ")
      
      add_badge(
        "festival_access",
        paste0(plan$ticket$day_label[1], " ", plan$ticket$ticket_type[1]),
        selected_label,
        "bi-ticket-perforated-fill",
        "coral",
        "FESTIVAL PASS",
        "pass",
        "Pass"
      )
      
      if (toupper(as.character(plan$ticket$ticket_type[1])) == "VIP") {
        add_badge(
          "vip_access",
          "VIP Weekend",
          "VIP festival access",
          "bi-stars",
          "gold",
          "ACCESS",
          "pass",
          "Pass"
        )
      }
    }
    
    # Stay badge - exact hotels assigned to selected festival days.
    assigned <- lapply(selected_days, function(day_id) {
      stay <- plan$lodging_by_day[[day_id]]
      if (is.null(stay) || nrow(stay) == 0) return(NULL)
      stay[1, , drop = FALSE]
    })
    assigned <- Filter(Negate(is.null), assigned)
    
    if (length(assigned) > 0) {
      hotel_ids <- vapply(assigned, function(x) as.character(x$lodging_id[1]), character(1))
      n_hotels <- length(unique(hotel_ids))
      
      add_badge(
        "san_diego_stay",
        if (n_hotels > 1) "Hotel Hopper" else "San Diego Stay",
        if (n_hotels > 1) {
          paste0(n_hotels, " hotels across your weekend")
        } else {
          as.character(assigned[[1]]$name[1])
        },
        if (n_hotels > 1) "bi-buildings-fill" else "bi-building-fill-check",
        "blue",
        "STAY",
        "stay",
        "Stay"
      )
      
      distances <- suppressWarnings(vapply(
        assigned,
        function(x) as.numeric(x$distance_from_venue_km[1]),
        numeric(1)
      ))
      
      if (all(!is.na(distances)) && max(distances) <= 1) {
        add_badge(
          "walkable_stay",
          "Walkable Stay",
          "Every assigned stay is within 1 km",
          "bi-person-walking",
          "green",
          "LOCATION",
          "stay",
          "Stay"
        )
      }
    }
    
    # One meaningful food badge. Clicking it reveals the actual restaurants.
    if (nrow(plan$restaurants) > 0) {
      cuisines <- unique(as.character(plan$restaurants$cuisine_type))
      cuisines <- cuisines[!is.na(cuisines) & nzchar(cuisines)]
      n_cuisines <- length(cuisines)
      n_restaurants <- nrow(plan$restaurants)
      
      food_title <- if (n_cuisines >= 3) {
        "Taste Explorer"
      } else if (n_cuisines == 2) {
        "Cuisine Mixer"
      } else {
        "Food Finder"
      }
      
      add_badge(
        "food_story",
        food_title,
        paste0(
          n_restaurants, " restaurant",
          if (n_restaurants == 1) "" else "s",
          " · ", n_cuisines, " cuisine",
          if (n_cuisines == 1) "" else "s"
        ),
        "bi-egg-fried",
        "orange",
        "FOOD",
        "food",
        "Food"
      )
    }
    
    # San Diego activity badge - actual selected free-time records.
    if (nrow(plan$activities) > 0) {
      n_activities <- nrow(plan$activities)
      
      add_badge(
        "san_diego_explorer",
        "San Diego Explorer",
        paste0(
          n_activities, " free-time stop",
          if (n_activities == 1) "" else "s"
        ),
        "bi-compass-fill",
        "purple",
        "FREE TIME",
        "activities",
        "Free time"
      )
      
      free_n <- sum(plan$activities$is_free_or_low_cost, na.rm = TRUE)
      if (free_n > 0) {
        add_badge(
          "free_fun",
          "Free Fun",
          paste0(free_n, " free / low-cost pick", if (free_n == 1) "" else "s"),
          "bi-piggy-bank-fill",
          "green",
          "SMART PICK",
          "free_activities",
          "Free time"
        )
      }
    }
    
    # Optional set badge - only if the user chose personal sets.
    if (nrow(plan$performances) > 0) {
      add_badge(
        "set_curator",
        "Set Curator",
        paste0(
          nrow(plan$performances), " saved set",
          if (nrow(plan$performances) == 1) "" else "s"
        ),
        "bi-music-note-beamed",
        "teal",
        "MY SCHEDULE",
        "sets",
        "Pass"
      )
    }
    
    badge_titles <- vapply(badges, function(x) x$title, character(1))
    selected_days_label <- if (length(selected_days) == 0) {
      "No festival days selected"
    } else {
      paste(unname(day_names[selected_days]), collapse = " + ")
    }
    
    list(
      badges = badges,
      badge_titles = badge_titles,
      selected_days_label = selected_days_label
    )
  })
  
  output$passport_share_button <- renderUI({
    model <- passport_model()
    if (length(model$badges) == 0) return(NULL)
    
    actionButton(
      "share_passport",
      "Share passport",
      class = "passport-share-btn"
    )
  })
  
  output$passport_content <- renderUI({
    model <- passport_model()
    
    if (length(model$badges) == 0) {
      return(
        div(
          class = "passport-empty passport-empty-v2",
          div(
            class = "passport-empty-medallion",
            tags$i(class = "bi bi-stars", `aria-hidden` = "true")
          ),
          h3("Your badges will appear here."),
          p("Start with a pass, then add a stay, food, and free-time choices."),
          actionButton("passport_start_plan", "Build my weekend", class = "btn-primary")
        )
      )
    }
    
    badge_card <- function(badge) {
      div(
        class = paste("experience-badge", paste0("badge-", badge$tone)),
        role = "button",
        tabindex = "0",
        title = paste0("View ", tolower(badge$title), " details"),
        onclick = sprintf(
          "Shiny.setInputValue('passport_badge_click','%s',{priority:'event'});",
          badge$id
        ),
        onkeypress = sprintf(
          "if(event.key==='Enter'){Shiny.setInputValue('passport_badge_click','%s',{priority:'event'});}",
          badge$id
        ),
        div(
          class = "experience-badge-ring",
          div(
            class = "experience-badge-icon",
            tags$i(class = paste("bi", badge$icon), `aria-hidden` = "true")
          )
        ),
        span(class = "experience-badge-kicker", badge$kicker),
        strong(class = "experience-badge-title", badge$title),
        span(class = "experience-badge-subtitle", badge$subtitle),
        span(class = "badge-view-hint", "View details")
      )
    }
    
    div(
      class = "passport-board",
      div(
        class = "passport-cover",
        div(
          span(class = "passport-cover-kicker", "BAYFRONT · SAN DIEGO · 2026"),
          h3("Your weekend, your badges."),
          p(model$selected_days_label)
        ),
        div(
          class = "passport-cover-mark",
          tags$i(class = "bi bi-sun-fill", `aria-hidden` = "true"),
          span("SD")
        )
      ),
      div(
        class = "passport-badge-header",
        div(
          h3("Your badges"),
          span(paste0(length(model$badges), " from your current plan"))
        ),
        span(class = "passport-plan-label", "CLICK TO EXPLORE")
      ),
      div(
        class = "experience-badge-grid",
        lapply(model$badges, badge_card)
      ),
      div(
        class = "passport-footnote",
        tags$i(class = "bi bi-info-circle", `aria-hidden` = "true"),
        span("Badges reflect your planned selections, not completed visits or check-ins.")
      )
    )
  })
  
  observeEvent(input$passport_start_plan, {
    nav_select("main_nav", "plan", session = session)
  })
  
  observeEvent(input$passport_badge_click, {
    model <- passport_model()
    matches <- Filter(
      function(x) identical(x$id, as.character(input$passport_badge_click)),
      model$badges
    )
    if (length(matches) == 0) return()
    
    badge <- matches[[1]]
    passport_modal_step(badge$planner_step)
    
    money <- function(x) paste0("$", formatC(as.numeric(x), format = "f", digits = 0, big.mark = ","))
    day_names <- c("1" = "Friday", "2" = "Saturday", "3" = "Sunday")
    
    modal_row <- function(icon, title, meta, value = NULL) {
      div(
        class = "passport-modal-row",
        div(
          class = "passport-modal-icon",
          tags$i(class = paste("bi", icon), `aria-hidden` = "true")
        ),
        div(
          class = "passport-modal-copy",
          strong(title),
          span(meta)
        ),
        if (!is.null(value)) strong(class = "passport-modal-value", value)
      )
    }
    
    content <- switch(
      badge$detail_type,
      
      pass = {
        if (nrow(plan$ticket) == 0) {
          p("No festival pass selected.")
        } else {
          selected_label <- paste(
            unname(day_names[as.character(plan$selected_days)]),
            collapse = " + "
          )
          div(
            class = "passport-modal-list",
            modal_row(
              "bi-ticket-perforated-fill",
              paste0(plan$ticket$day_label[1], " ", plan$ticket$ticket_type[1]),
              selected_label,
              money(plan$ticket$price[1])
            )
          )
        }
      },
      
      stay = {
        rows <- lapply(plan$selected_days, function(day_id) {
          stay <- plan$lodging_by_day[[as.character(day_id)]]
          if (is.null(stay) || nrow(stay) == 0) return(NULL)
          modal_row(
            "bi-building",
            as.character(stay$name[1]),
            paste0(
              unname(day_names[as.character(day_id)]), " · ",
              as.character(stay$property_type[1]), " · ",
              round(as.numeric(stay$distance_from_venue_km[1]), 2),
              " km from venue"
            ),
            paste0(money(stay$price_per_night[1]), "/night")
          )
        })
        rows <- Filter(Negate(is.null), rows)
        div(class = "passport-modal-list", rows)
      },
      
      food = {
        rows <- lapply(seq_len(nrow(plan$restaurants)), function(i) {
          r <- plan$restaurants[i, , drop = FALSE]
          modal_row(
            "bi-cup-hot",
            as.character(r$restaurant_name[1]),
            paste0(
              as.character(r$cuisine_type[1]),
              if (!is.na(r$area[1]) && nzchar(as.character(r$area[1]))) {
                paste0(" · ", as.character(r$area[1]))
              } else {
                ""
              },
              " · ",
              round(as.numeric(r$distance_from_venue_km[1]), 2),
              " km from venue"
            ),
            paste0(money(r$price_per_meal[1]), "/meal")
          )
        })
        div(class = "passport-modal-list", rows)
      },
      
      activities = {
        rows <- lapply(seq_len(nrow(plan$activities)), function(i) {
          a <- plan$activities[i, , drop = FALSE]
          modal_row(
            "bi-geo-alt",
            as.character(a$activity_name[1]),
            paste0(
              as.character(a$activity_type[1]), " · ",
              as.character(a$price_category[1])
            ),
            money(a$adult_price_usd[1])
          )
        })
        div(class = "passport-modal-list", rows)
      },
      
      free_activities = {
        d <- plan$activities[plan$activities$is_free_or_low_cost %in% TRUE, , drop = FALSE]
        rows <- lapply(seq_len(nrow(d)), function(i) {
          a <- d[i, , drop = FALSE]
          modal_row(
            "bi-piggy-bank",
            as.character(a$activity_name[1]),
            paste0(
              as.character(a$activity_type[1]), " · ",
              as.character(a$price_category[1])
            ),
            money(a$adult_price_usd[1])
          )
        })
        div(class = "passport-modal-list", rows)
      },
      
      sets = {
        d <- plan$performances[
          order(plan$performances$day_id, time_to_seconds(plan$performances$start_time)),
          , drop = FALSE
        ]
        rows <- lapply(seq_len(nrow(d)), function(i) {
          p <- d[i, , drop = FALSE]
          modal_row(
            "bi-music-note-beamed",
            as.character(p$artist_name[1]),
            paste0(
              as.character(p$day_name[1]), " · ",
              as.character(p$stage_name[1]), " · ",
              substr(as.character(p$start_time[1]), 1, 5)
            )
          )
        })
        div(class = "passport-modal-list", rows)
      },
      
      p("This badge is based on your current plan.")
    )
    
    showModal(
      modalDialog(
        title = badge$title,
        div(
          class = "passport-modal",
          div(
            class = paste("passport-modal-badge", paste0("badge-", badge$tone)),
            tags$i(class = paste("bi", badge$icon), `aria-hidden` = "true"),
            div(
              span(badge$kicker),
              strong(badge$subtitle)
            )
          ),
          content
        ),
        easyClose = TRUE,
        size = "m",
        footer = tagList(
          actionButton(
            "passport_modal_edit",
            "Edit this part of my plan",
            class = "btn-outline-primary"
          ),
          modalButton("Close")
        )
      )
    )
  })
  
  observeEvent(input$passport_modal_edit, {
    step <- passport_modal_step()
    removeModal()
    nav_select("main_nav", "plan", session = session)
    nav_select("plan_step", step, session = session)
  })
  
  observeEvent(input$share_passport, {
    model <- passport_model()
    if (length(model$badges) == 0) return()
    
    # Keep the shared message short enough for messages/social apps,
    # while still reflecting the user's actual current plan.
    text <- paste0(
      "My Bayfront Drift Passport · San Diego 2026\n",
      model$selected_days_label,
      "\n\n",
      paste0("Badges: ", paste(model$badge_titles, collapse = " · ")),
      "\n\n",
      "Built with Bayfront Drift."
    )
    
    badge_pills <- lapply(model$badge_titles, function(x) {
      span(class = "share-badge-pill", x)
    })
    
    showModal(
      modalDialog(
        title = NULL,
        size = "m",
        easyClose = TRUE,
        footer = NULL,
        div(
          class = "passport-share-modal",
          div(
            class = "passport-share-modal-head",
            div(
              span(class = "eyebrow", "READY TO SHARE"),
              h3("Share your Bayfront Drift Passport"),
              p("Send your personalized festival profile or copy it anywhere.")
            ),
            div(
              class = "passport-share-mini-mark",
              tags$i(class = "bi bi-sun-fill", `aria-hidden` = "true"),
              span("SD")
            )
          ),
          div(
            class = "passport-share-preview",
            strong("My Bayfront Drift Passport"),
            span(model$selected_days_label),
            div(class = "share-badge-pills", badge_pills)
          ),
          tags$label(
            `for` = "passport_share_text",
            class = "passport-share-label",
            "Share summary"
          ),
          tags$textarea(
            id = "passport_share_text",
            class = "form-control passport-share-text",
            readonly = "readonly",
            rows = 5,
            text
          ),
          div(
            class = "passport-share-actions",
            tags$button(
              type = "button",
              class = "btn btn-primary passport-copy-btn",
              onclick = "copyPassportSummary();",
              tags$i(class = "bi bi-copy", `aria-hidden` = "true"),
              " Copy summary"
            ),
            tags$button(
              type = "button",
              class = "btn btn-outline-primary passport-native-share-btn",
              onclick = "nativeSharePassport();",
              tags$i(class = "bi bi-share", `aria-hidden` = "true"),
              " Use device share"
            ),
            actionButton(
              "close_passport_share",
              "Close",
              class = "btn btn-link passport-share-close"
            )
          ),
          p(
            class = "passport-share-help",
            tags$i(class = "bi bi-info-circle", `aria-hidden` = "true"),
            " Device share depends on browser support. Copy summary works as the reliable fallback."
          )
        )
      )
    )
  })
  
  observeEvent(input$close_passport_share, {
    removeModal()
  })
  
  observeEvent(input$passport_share_status, {
    if (identical(input$passport_share_status, "shared")) {
      showNotification(
        "Passport shared.",
        type = "message",
        duration = 2
      )
    } else if (identical(input$passport_share_status, "copied")) {
      showNotification(
        "Passport summary copied. Paste it into Messages, WhatsApp, email, or social media.",
        type = "message",
        duration = 4
      )
    } else if (identical(input$passport_share_status, "native_unavailable")) {
      showNotification(
        "Native device sharing is not supported in this browser. Use Copy summary instead.",
        type = "warning",
        duration = 4
      )
    } else if (identical(input$passport_share_status, "failed")) {
      showNotification(
        "Automatic copy was blocked. Select the share summary and copy it manually.",
        type = "warning",
        duration = 4
      )
    }
  })
  
  # ==========================================================
  # MY PLAN
  # ==========================================================
  
  stat_tile <- function(label, value, extra_class = NULL) {
    classes <- paste(c("stat-tile", extra_class), collapse = " ")
    div(class = classes,
        span(class = "stat-label", label),
        span(class = "stat-value", value))
  }
  
  output$stat_ticket <- renderUI(
    stat_tile("Festival pass", if (nrow(plan$ticket) == 0) "None" else paste0(plan$ticket$day_label[1], " ", plan$ticket$ticket_type[1])))
  
  output$stat_lodging <- renderUI({
    assigned <- lapply(plan$selected_days, function(day_id) {
      x <- plan$lodging_by_day[[as.character(day_id)]]
      if (is.null(x) || nrow(x) == 0) return(NULL)
      x
    })
    assigned <- assigned[!vapply(assigned, is.null, logical(1))]
    
    n_nights <- length(assigned)
    n_hotels <- if (n_nights == 0) {
      0
    } else {
      length(unique(vapply(
        assigned,
        function(x) as.character(x$lodging_id[1]),
        character(1)
      )))
    }
    
    value <- if (n_nights == 0) {
      "None"
    } else if (n_hotels == 1) {
      paste0(n_nights, " night", ifelse(n_nights == 1, "", "s"), " · 1 hotel")
    } else {
      paste0(n_nights, " nights · ", n_hotels, " hotels")
    }
    
    stat_tile("Accommodation", value)
  })
  
  output$stat_restaurants <- renderUI(
    stat_tile("Restaurants", nrow(plan$restaurants)))
  output$stat_activities <- renderUI(
    stat_tile("Activities", nrow(plan$activities)))
  
  output$plan_badge <- renderUI({
    assigned_stays <- if (length(plan$selected_days) == 0) {
      0
    } else {
      sum(vapply(
        plan$selected_days,
        function(day_id) {
          stay <- plan$lodging_by_day[[as.character(day_id)]]
          !is.null(stay) && nrow(stay) > 0
        },
        logical(1)
      ))
    }
    
    n <- nrow(plan$ticket) + assigned_stays + nrow(plan$performances) +
      nrow(plan$restaurants) + nrow(plan$activities)
    
    if (n == 0) return(NULL)
    span(class = "nav-badge", n)
  })
  
  output$plan_conflict_banner <- renderUI({
    conflicts <- find_conflicts(plan$performances)
    if (length(conflicts) == 0) return(NULL)
    div(
      class = "conflict-banner",
      tags$i(class = "bi bi-exclamation-triangle", `aria-hidden` = "true"),
      strong(" Selected-set conflict: "),
      paste(conflicts, collapse = "; ")
    )
  })
  
  # Plan summary metrics.
  plan_snapshot <- reactive({
    conflicts <- find_conflicts(plan$performances)
    
    selected_day_count <- length(plan$selected_days)
    ticket_ready <- (
      nrow(plan$ticket) > 0 &&
        selected_day_count == as.integer(plan$ticket$days_covered[1])
    )
    
    lodging_ready <- (
      selected_day_count > 0 &&
        all(vapply(
          plan$selected_days,
          function(day_id) {
            stay <- plan$lodging_by_day[[as.character(day_id)]]
            !is.null(stay) && nrow(stay) > 0
          },
          logical(1)
        ))
    )
    
    criteria <- c(
      ticket_ready,
      lodging_ready,
      nrow(plan$restaurants) > 0,
      nrow(plan$activities) > 0
    )
    
    readiness <- round(mean(criteria) * 100)
    
    stays_assigned <- if (selected_day_count == 0) {
      0
    } else {
      sum(vapply(
        plan$selected_days,
        function(day_id) {
          stay <- plan$lodging_by_day[[as.character(day_id)]]
          !is.null(stay) && nrow(stay) > 0
        },
        logical(1)
      ))
    }
    
    cuisines <- if (nrow(plan$restaurants) == 0) {
      0
    } else {
      length(unique(plan$restaurants$cuisine_type))
    }
    
    affordable <- if (nrow(plan$activities) == 0) {
      0
    } else {
      sum(plan$activities$is_free_or_low_cost, na.rm = TRUE)
    }
    
    ticket_cost <- if (nrow(plan$ticket) == 0) 0 else as.numeric(plan$ticket$price[1])
    
    lodging_cost <- if (selected_day_count == 0) {
      0
    } else {
      sum(vapply(
        plan$selected_days,
        function(day_id) {
          stay <- plan$lodging_by_day[[as.character(day_id)]]
          if (is.null(stay) || nrow(stay) == 0) 0 else as.numeric(stay$price_per_night[1])
        },
        numeric(1)
      ))
    }
    
    food_cost <- if (nrow(plan$restaurants) == 0) {
      0
    } else {
      sum(as.numeric(plan$restaurants$price_per_meal), na.rm = TRUE)
    }
    
    activity_cost <- if (nrow(plan$activities) == 0) {
      0
    } else {
      sum(as.numeric(plan$activities$adult_price_usd), na.rm = TRUE)
    }
    
    list(
      readiness = readiness,
      core_count = sum(criteria),
      selected_days = selected_day_count,
      stays_assigned = stays_assigned,
      cuisines = cuisines,
      affordable = affordable,
      ticket_cost = ticket_cost,
      lodging_cost = lodging_cost,
      food_cost = food_cost,
      activity_cost = activity_cost,
      total_cost = ticket_cost + lodging_cost + food_cost + activity_cost,
      conflicts = length(conflicts)
    )
  })
  
  output$plan_ready_pill <- renderUI({
    v <- plan_snapshot()
    ready <- v$core_count == 4
    div(
      class = if (ready) "plan-ready-pill is-ready" else "plan-ready-pill",
      tags$i(
        class = if (ready) "bi bi-check-circle-fill" else "bi bi-circle",
        `aria-hidden` = "true"
      ),
      span(paste0(v$core_count, "/4 sections"))
    )
  })
  
  output$plan_story <- renderUI({
    if (length(plan$selected_days) == 0) {
      return(
        status_card(
          "bi-calendar3",
          "Your story starts with a pass",
          "Choose your festival pass and day(s) to build the weekend."
        )
      )
    }
    
    day_names <- c("1" = "Friday", "2" = "Saturday", "3" = "Sunday")
    schedule <- performance_options()
    rec <- recommended_transit()
    
    cards <- lapply(seq_along(plan$selected_days), function(index) {
      day_id <- as.character(plan$selected_days[index])
      day_name <- unname(day_names[day_id])
      
      stay <- plan$lodging_by_day[[day_id]]
      has_stay <- !is.null(stay) && nrow(stay) > 0
      
      day_schedule <- if (nrow(schedule) == 0) {
        data.frame()
      } else {
        schedule[as.character(schedule$day_id) == day_id, , drop = FALSE]
      }
      
      day_date <- if (nrow(day_schedule) > 0 && "day_date" %in% names(day_schedule)) {
        format(as.Date(day_schedule$day_date[1]), "%b %d")
      } else {
        c("1" = "Aug 21", "2" = "Aug 22", "3" = "Aug 23")[day_id]
      }
      
      transit <- if (nrow(rec) == 0) {
        data.frame()
      } else {
        rec[as.character(rec$day_id) == day_id, , drop = FALSE]
      }
      
      target <- departure_target_for_day(day_id)
      
      if (nrow(transit) > 0 && !is.na(transit$estimated_minutes[1])) {
        depart <- suggested_departure_for_day(
          day_id,
          transit$estimated_minutes[1],
          transit$departure_time[1]
        )
        travel_title <- paste0(transit$mode[1], " · ", transit$estimated_minutes[1], " min")
        
        travel_meta <- if (identical(depart$target_type, "selected_set")) {
          paste0(
            "Leave ", depart$time,
            " · for ", depart$target_artist,
            " at ", depart$target_time
          )
        } else if (identical(depart$target_type, "festival_opening")) {
          paste0(
            "Leave ", depart$time,
            " · first set at ", depart$target_time
          )
        } else {
          paste0("Suggested leave ", depart$time)
        }
      } else {
        travel_title <- if (has_stay) "Travel estimate unavailable" else "Choose a stay first"
        travel_meta <- if (has_stay) "No route estimate for this hotel/day" else "Then we can build your trip to the venue"
      }
      
      if (has_stay) {
        stay_title <- as.character(stay$name[1])
        stay_meta <- paste0(
          "$", formatC(stay$price_per_night[1], format = "f", digits = 0),
          " · ", round(stay$distance_from_venue_km[1], 2), " km from venue"
        )
      } else {
        stay_title <- "No hotel assigned"
        stay_meta <- "Add a stay for this festival day"
      }
      
      selected_sets <- if (nrow(plan$performances) == 0) {
        0
      } else {
        sum(as.character(plan$performances$day_id) == day_id)
      }
      
      if (nrow(day_schedule) > 0) {
        first_idx <- which.min(time_to_seconds(day_schedule$start_time))
        first_set <- day_schedule[first_idx, , drop = FALSE]
        perf_title <- paste0(
          nrow(day_schedule), " performances · ",
          length(unique(day_schedule$stage_id)), " stages"
        )
        
        if (
          selected_sets > 0 &&
          !is.null(target) &&
          nrow(target) > 0 &&
          "target_type" %in% names(target) &&
          identical(as.character(target$target_type[1]), "selected_set")
        ) {
          perf_meta <- paste0(
            "Your first pick ",
            substr(as.character(target$start_time[1]), 1, 5),
            " · ",
            target$artist_name[1]
          )
        } else {
          perf_meta <- paste0(
            "First set ", substr(as.character(first_set$start_time[1]), 1, 5),
            " · ", first_set$artist_name[1]
          )
        }
      } else {
        perf_title <- "Festival schedule unavailable"
        perf_meta <- "No performance data found for this day"
      }
      
      story_step <- function(icon, label, title, meta, accent) {
        div(
          class = paste("day-story-step", paste0("story-", accent)),
          div(
            class = "day-story-icon",
            tags$i(class = paste("bi", icon), `aria-hidden` = "true")
          ),
          div(
            class = "day-story-copy",
            span(class = "day-story-label", label),
            strong(title),
            span(meta)
          )
        )
      }
      
      div(
        class = "day-story-card",
        div(
          class = "day-story-head",
          div(
            span(class = "day-story-index", paste0("DAY ", index)),
            h4(day_name),
            span(day_date)
          ),
          if (selected_sets > 0) {
            span(
              class = "day-story-saved",
              paste0(selected_sets, " set", if (selected_sets == 1) "" else "s", " saved")
            )
          }
        ),
        div(
          class = "day-story-flow",
          story_step(
            "bi-building",
            "STAY",
            stay_title,
            stay_meta,
            "stay"
          ),
          div(class = "day-story-arrow", tags$i(class = "bi bi-arrow-right")),
          story_step(
            "bi-geo-alt-fill",
            "GET THERE",
            travel_title,
            travel_meta,
            "travel"
          ),
          div(class = "day-story-arrow", tags$i(class = "bi bi-arrow-right")),
          story_step(
            "bi-music-note-beamed",
            "FESTIVAL",
            perf_title,
            perf_meta,
            "festival"
          )
        )
      )
    })
    
    div(class = "day-story-list", cards)
  })
  
  output$plan_experience_picks <- renderUI({
    pick_card <- function(icon, title, meta, value = NULL, tag = NULL) {
      div(
        class = "experience-pick",
        div(
          class = "experience-pick-icon",
          tags$i(class = paste("bi", icon), `aria-hidden` = "true")
        ),
        div(
          class = "experience-pick-copy",
          strong(title),
          span(meta),
          if (!is.null(tag)) span(class = "experience-pick-tag", tag)
        ),
        if (!is.null(value)) strong(class = "experience-pick-value", value)
      )
    }
    
    food_items <- if (nrow(plan$restaurants) == 0) {
      list(
        div(
          class = "story-empty",
          tags$i(class = "bi bi-cup-hot"),
          span("No restaurants selected yet.")
        )
      )
    } else {
      lapply(seq_len(nrow(plan$restaurants)), function(i) {
        r <- plan$restaurants[i, , drop = FALSE]
        pick_card(
          "bi-cup-hot",
          as.character(r$restaurant_name[1]),
          paste0(
            as.character(r$cuisine_type[1]),
            if (!is.na(r$area[1]) && nzchar(as.character(r$area[1]))) {
              paste0(" · ", as.character(r$area[1]))
            } else {
              ""
            }
          ),
          paste0("$", formatC(r$price_per_meal[1], format = "f", digits = 0))
        )
      })
    }
    
    activity_items <- if (nrow(plan$activities) == 0) {
      list(
        div(
          class = "story-empty",
          tags$i(class = "bi bi-compass"),
          span("No free-time stops selected yet.")
        )
      )
    } else {
      lapply(seq_len(nrow(plan$activities)), function(i) {
        a <- plan$activities[i, , drop = FALSE]
        price <- as.numeric(a$adult_price_usd[1])
        pick_card(
          "bi-geo-alt",
          as.character(a$activity_name[1]),
          as.character(a$activity_type[1]),
          if (price == 0) "Free" else paste0("$", formatC(price, format = "f", digits = 0)),
          if (isTRUE(a$is_free_or_low_cost[1])) "FREE / LOW-COST" else NULL
        )
      })
    }
    
    tagList(
      div(
        class = "experience-story-grid",
        div(
          class = "experience-story-group",
          div(
            class = "experience-story-head",
            div(
              tags$i(class = "bi bi-cup-hot-fill"),
              div(
                strong("Food"),
                span(paste0(nrow(plan$restaurants), " selected"))
              )
            ),
            actionButton("story_edit_food", "Edit", class = "story-edit-btn")
          ),
          div(class = "experience-pick-list", food_items)
        ),
        div(
          class = "experience-story-group",
          div(
            class = "experience-story-head",
            div(
              tags$i(class = "bi bi-sun-fill"),
              div(
                strong("San Diego stops"),
                span(paste0(nrow(plan$activities), " selected"))
              )
            ),
            actionButton("story_edit_activities", "Edit", class = "story-edit-btn")
          ),
          div(class = "experience-pick-list", activity_items)
        )
      )
    )
  })
  
  observeEvent(input$story_edit_food, {
    nav_select("main_nav", "plan", session = session)
    nav_select("plan_step", "Food", session = session)
  })
  
  observeEvent(input$story_edit_activities, {
    nav_select("main_nav", "plan", session = session)
    nav_select("plan_step", "Free time", session = session)
  })
  
  output$stat_total <- renderUI({
    v <- plan_snapshot()
    stat_tile(
      "Estimated total",
      paste0("$", formatC(v$total_cost, format = "f", digits = 2, big.mark = ",")),
      extra_class = "stat-tile-total"
    )
  })
  
  
  output$weekend_snapshot <- renderUI({
    v <- plan_snapshot()
    
    conflict_status <- if (nrow(plan$performances) == 0) {
      div(
        class = "snapshot-status neutral",
        tags$i(class = "bi bi-music-note-list", `aria-hidden` = "true"),
        " Personal set schedule is optional."
      )
    } else if (v$conflicts == 0) {
      div(
        class = "snapshot-status good",
        tags$i(class = "bi bi-check-circle", `aria-hidden` = "true"),
        " No conflicts in your selected sets."
      )
    } else {
      div(
        class = "snapshot-status warning",
        tags$i(class = "bi bi-exclamation-triangle", `aria-hidden` = "true"),
        paste0(" ", v$conflicts, " selected-set conflict(s) detected.")
      )
    }
    
    tagList(
      div(
        class = "readiness-head",
        div(
          span(class = "readiness-label", "Plan sections complete"),
          span(class = "readiness-value", paste0(v$core_count, "/4"))
        )
      ),
      div(
        class = "readiness-track",
        div(class = "readiness-fill", style = paste0("width:", v$readiness, "%;"))
      ),
      div(
        class = "snapshot-grid",
        div(
          class = "snapshot-item",
          strong(v$selected_days),
          span("festival days selected")
        ),
        div(
          class = "snapshot-item",
          strong(paste0(v$stays_assigned, "/", max(v$selected_days, 1))),
          span("festival days with a stay")
        ),
        div(
          class = "snapshot-item",
          strong(v$cuisines),
          span("cuisines selected")
        ),
        div(
          class = "snapshot-item",
          strong(v$affordable),
          span("free / low-cost activities")
        )
      ),
      conflict_status
    )
  })
  
  output$budget_explanation <- renderUI({
    v <- plan_snapshot()
    money <- function(x) paste0("$", formatC(x, format = "f", digits = 2, big.mark = ","))
    
    subtotal <- function(icon, label, amount, note, tone) {
      div(
        class = paste("cost-summary-item", paste0("cost-", tone)),
        div(
          class = "cost-summary-icon",
          tags$i(class = paste("bi", icon), `aria-hidden` = "true")
        ),
        div(
          class = "cost-summary-copy",
          span(label),
          strong(money(amount)),
          tags$small(note)
        )
      )
    }
    
    div(
      class = "cost-summary-wrap",
      div(
        class = "cost-summary-grid",
        subtotal(
          "bi-ticket-perforated-fill",
          "Festival pass",
          v$ticket_cost,
          if (nrow(plan$ticket) == 0) "Not selected" else paste0(plan$ticket$day_label[1], " ", plan$ticket$ticket_type[1]),
          "coral"
        ),
        subtotal(
          "bi-building-fill",
          "Accommodation",
          v$lodging_cost,
          paste0(v$stays_assigned, " night", if (v$stays_assigned == 1) "" else "s"),
          "blue"
        ),
        subtotal(
          "bi-cup-hot-fill",
          "Food",
          v$food_cost,
          paste0(nrow(plan$restaurants), " meal", if (nrow(plan$restaurants) == 1) "" else "s"),
          "orange"
        ),
        subtotal(
          "bi-geo-alt-fill",
          "Activities",
          v$activity_cost,
          paste0(nrow(plan$activities), " admission", if (nrow(plan$activities) == 1) "" else "s"),
          "green"
        )
      ),
      tags$details(
        class = "cost-basis-details",
        tags$summary("How this estimate is calculated"),
        div(
          class = "cost-basis-content",
          span("1 hotel night per selected festival day"),
          span("1 meal per selected restaurant"),
          span("Listed adult activity admission"),
          span("Selected festival pass"),
          tags$small("Not included: transportation fares, taxes/fees, extra meals, shopping, or other personal spending.")
        )
      )
    )
  })
  
  output$plan_stay_summary <- renderUI({
    if (length(plan$selected_days) == 0) {
      return(status_card(
        "bi-buildings",
        "No festival days selected",
        "Choose your pass and festival day(s) first."
      ))
    }
    
    day_names <- c("1" = "Friday", "2" = "Saturday", "3" = "Sunday")
    
    rows <- lapply(plan$selected_days, function(day_id) {
      stay <- plan$lodging_by_day[[as.character(day_id)]]
      
      if (is.null(stay) || nrow(stay) == 0) {
        div(
          class = "stay-day-row",
          div(
            span(class = "eyebrow", unname(day_names[as.character(day_id)])),
            strong("No accommodation assigned")
          ),
          span(class = "stay-day-price", "—")
        )
      } else {
        div(
          class = "stay-day-row",
          div(
            span(class = "eyebrow", unname(day_names[as.character(day_id)])),
            strong(stay$name[1]),
            span(
              paste(
                stay$property_type[1],
                paste0(round(stay$distance_from_venue_km[1], 2), " km from venue"),
                sep = " · "
              )
            )
          ),
          span(
            class = "stay-day-price",
            paste0("$", formatC(stay$price_per_night[1], format = "f", digits = 0))
          )
        )
      }
    })
    
    div(class = "stay-assignment-card", rows)
  })
  
  output$plan_travel_summary <- renderUI({
    if (length(plan$selected_days) == 0) {
      return(status_card(
        "bi-bus-front",
        "No festival days selected",
        "Choose your pass and festival day(s) first."
      ))
    }
    
    rec <- recommended_transit()
    
    if (nrow(rec) == 0) {
      return(status_card(
        "bi-bus-front",
        "Travel estimate unavailable",
        "Assign accommodation to your selected festival day(s) first."
      ))
    }
    
    cards <- lapply(seq_len(nrow(rec)), function(i) {
      depart_info <- if (is.na(rec$estimated_minutes[i])) {
        list(time = "—", basis = "No travel estimate available")
      } else {
        suggested_departure_for_day(
          rec$day_id[i],
          rec$estimated_minutes[i],
          rec$departure_time[i]
        )
      }
      
      stops_text <- if (is.na(rec$num_stops[i])) {
        ""
      } else if (rec$num_stops[i] == 0) {
        "Direct"
      } else if (rec$num_stops[i] == 1) {
        "1 stop"
      } else {
        paste0(rec$num_stops[i], " stops")
      }
      
      perf_text <- selected_performances_for_day(rec$day_id[i])
      if (is.null(perf_text) || perf_text == "") {
        perf_text <- depart_info$basis
      }
      
      div(
        class = "plan-travel-card",
        div(
          class = "plan-travel-head",
          div(
            strong(rec$day_name[i]),
            span(paste0(rec$accommodation_name[i], " · ", rec$mode[i]))
          ),
          div(
            class = "plan-travel-duration",
            strong(
              ifelse(
                is.na(rec$estimated_minutes[i]),
                "Unavailable",
                paste0(rec$estimated_minutes[i], " min")
              )
            ),
            span(stops_text)
          )
        ),
        div(
          class = "plan-travel-grid",
          div(
            span(class = "plan-travel-label", "Suggested leave"),
            strong(depart_info$time)
          ),
          div(
            span(class = "plan-travel-label", "Festival plan"),
            span(perf_text)
          )
        ),
        span(class = "plan-travel-source", rec$estimate_source[i])
      )
    })
    
    tagList(
      div(class = "plan-travel-list", cards),
      p(
        class = "small-note",
        "If you save performances, suggested leave time follows your earliest saved set for that day. Otherwise it uses the first scheduled festival set. The calculation includes travel time plus a 60-minute arrival buffer; when no database route is available, walking time is approximated from stored venue distance at 5 km/h."
      )
    )
  })
  
  output$festival_schedule_overview <- renderUI({
    if (length(plan$selected_days) == 0) {
      return(status_card(
        "bi-calendar-event",
        "No festival days selected",
        "Choose your festival pass and day(s) first."
      ))
    }
    
    d <- performance_options()
    if (nrow(d) == 0) {
      return(status_card(
        "bi-music-note-beamed",
        "Festival schedule unavailable",
        "No performance schedule was found for the selected day(s)."
      ))
    }
    
    day_ids <- sort(unique(d$day_id))
    
    sections <- lapply(day_ids, function(day_id) {
      dd <- d[d$day_id == day_id, , drop = FALSE]
      dd <- dd[order(time_to_seconds(dd$start_time), dd$stage_name), , drop = FALSE]
      
      div(
        class = "festival-day-summary",
        div(
          class = "festival-day-summary-head",
          h3(dd$day_name[1]),
          span(paste0(nrow(dd), " performances · ", length(unique(dd$stage_id)), " stages"))
        ),
        div(
          class = "festival-time-groups",
          lapply(split(dd, substr(as.character(dd$start_time), 1, 5)), function(slot) {
            div(
              class = "festival-time-row",
              strong(substr(as.character(slot$start_time[1]), 1, 5)),
              span(
                paste0(
                  slot$artist_name, " · ", slot$stage_name,
                  collapse = "  |  "
                )
              )
            )
          })
        )
      )
    })
    
    div(class = "festival-overview-grid", sections)
  })
  
  output$plan_schedule <- renderUI({
    if (nrow(plan$performances) == 0) {
      return(NULL)
    }
    
    d <- plan$performances
    d <- d[order(d$day_id, time_to_seconds(d$start_time)), , drop = FALSE]
    
    day_ids <- sort(unique(d$day_id))
    day_sections <- lapply(day_ids, function(day_id) {
      dd <- d[d$day_id == day_id, , drop = FALSE]
      
      div(
        class = "itinerary-day",
        div(
          class = "itinerary-day-head",
          h3(dd$day_name[1]),
          span(paste(nrow(dd), ifelse(nrow(dd) == 1, "set", "sets")))
        ),
        div(
          class = "itinerary-list",
          lapply(seq_len(nrow(dd)), function(i) {
            div(
              class = "itinerary-item",
              div(
                class = "itinerary-time",
                strong(substr(as.character(dd$start_time[i]), 1, 5)),
                span(paste0("–", substr(as.character(dd$end_time[i]), 1, 5)))
              ),
              div(
                class = "itinerary-copy",
                strong(dd$artist_name[i]),
                span(paste(dd$genre[i], "·", dd$stage_name[i]))
              )
            )
          })
        )
      )
    })
    
    tagList(
      h4(class = "my-sets-title", "My sets"),
      div(class = "itinerary-grid", day_sections)
    )
  })
  
  output$plan_restaurant_table <- renderDT({
    if (nrow(plan$restaurants) == 0)
      return(empty_plan_table("No restaurants selected yet."))
    d <- plan$restaurants[, c("restaurant_name", "cuisine_type", "rating",
                              "price_per_meal", "area", "distance_from_venue_km")]
    names(d) <- c("Restaurant", "Cuisine", "Rating",
                  "Price / meal", "Area", "Distance (km)")
    datatable(
      d,
      rownames = FALSE,
      options = list(pageLength = 6, dom = "tp"),
      class = "compact"
    ) |>
      formatRound("Rating", 1) |>
      formatCurrency("Price / meal", "$", digits = 0) |>
      formatRound("Distance (km)", 2)
  })
  
  output$plan_activity_table <- renderDT({
    if (nrow(plan$activities) == 0)
      return(empty_plan_table("No activities selected yet."))
    d <- plan$activities[, c("activity_name", "activity_type",
                             "adult_price_usd", "is_free_or_low_cost")]
    d$is_free_or_low_cost <- ifelse(d$is_free_or_low_cost, "Yes", "No")
    names(d) <- c("Activity", "Type", "Adult price", "Free / low-cost")
    datatable(
      d,
      rownames = FALSE,
      options = list(pageLength = 6, dom = "tp"),
      class = "compact"
    ) |>
      formatCurrency("Adult price", "$", digits = 2)
  })
  
  observeEvent(input$clear_plan, {
    plan$ticket        <- data.frame()
    plan$selected_days <- character(0)
    plan$lodging       <- data.frame()
    plan$lodging_by_day <- list()
    plan$performances <- data.frame()
    plan$restaurants  <- data.frame()
    plan$activities   <- data.frame()
    showNotification("Your plan was cleared.", type = "message")
  })
  
  # -- Download ----------------------------------------------
  
  plan_export <- reactive({
    rows <- list()
    day_names <- c("1"="Friday", "2"="Saturday", "3"="Sunday")
    if (nrow(plan$ticket) > 0) {
      selected_label <- paste(unname(day_names[as.character(plan$selected_days)]), collapse = " + ")
      rows[[length(rows)+1]] <- data.frame(Category="Festival pass", Item=paste(plan$ticket$day_label[1], plan$ticket$ticket_type[1]), Details=selected_label, Price_or_tier=paste0("$", formatC(plan$ticket$price[1], format="f", digits=2)), stringsAsFactors=FALSE)
    }
    
    if (length(plan$selected_days) > 0) {
      day_names <- c("1" = "Friday", "2" = "Saturday", "3" = "Sunday")
      for (day_id in plan$selected_days) {
        stay <- plan$lodging_by_day[[as.character(day_id)]]
        if (!is.null(stay) && nrow(stay) > 0) {
          rows[[length(rows) + 1]] <- data.frame(
            Category = "Accommodation",
            Item = paste0(unname(day_names[as.character(day_id)]), " · ", stay$name[1]),
            Details = paste0(
              stay$property_type[1], " · ",
              round(stay$distance_from_venue_km[1], 2), " km from venue"
            ),
            Price_or_tier = paste0(
              "$", formatC(stay$price_per_night[1], format = "f", digits = 2),
              "/night"
            ),
            stringsAsFactors = FALSE
          )
        }
      }
    }
    
    rec <- recommended_transit()
    if (nrow(rec) > 0) {
      suggested_leave <- vapply(seq_len(nrow(rec)), function(i) {
        suggested_departure_for_day(
          rec$day_id[i],
          rec$estimated_minutes[i],
          rec$departure_time[i]
        )$time
      }, character(1))
      
      rows[[length(rows) + 1]] <- data.frame(
        Category = "Transportation",
        Item = paste0(rec$day_name, " trip"),
        Details = paste(
          rec$mode,
          paste0(rec$estimated_minutes, " min"),
          paste0("Suggested leave ", suggested_leave),
          sep = " | "
        ),
        Price_or_tier = "Trip recommendation",
        stringsAsFactors = FALSE
      )
    }
    
    if (nrow(plan$performances) > 0) rows[[length(rows) + 1]] <- data.frame(
      Category = "Performance", Item = plan$performances$artist_name,
      Details = paste(plan$performances$day_name, plan$performances$stage_name,
                      plan$performances$start_time, sep = " | "),
      Price_or_tier = "Festival performance", stringsAsFactors = FALSE)
    
    if (nrow(plan$restaurants) > 0) rows[[length(rows) + 1]] <- data.frame(
      Category = "Restaurant", Item = plan$restaurants$restaurant_name,
      Details = paste(plan$restaurants$cuisine_type, plan$restaurants$area, sep = " | "),
      Price_or_tier = paste0("$", formatC(plan$restaurants$price_per_meal, format = "f", digits = 2), "/meal"), stringsAsFactors = FALSE)
    
    if (nrow(plan$activities) > 0) rows[[length(rows) + 1]] <- data.frame(
      Category = "Activity", Item = plan$activities$activity_name,
      Details = paste(plan$activities$activity_type,
                      plan$activities$price_category, sep = " | "),
      Price_or_tier = paste0("$", formatC(plan$activities$adult_price_usd,
                                          format = "f", digits = 2)), stringsAsFactors = FALSE)
    
    v <- plan_snapshot()
    if (length(rows) > 0) rows[[length(rows)+1]] <- data.frame(Category="Total", Item="Estimated weekend total", Details="Pass + lodging + selected meals + selected activities", Price_or_tier=paste0("$", formatC(v$total_cost, format="f", digits=2)), stringsAsFactors=FALSE)
    if (length(rows) == 0) return(data.frame(
      Category = character(), Item = character(),
      Details = character(), Price_or_tier = character()))
    do.call(rbind, rows)
  })
  
  output$download_plan <- downloadHandler(
    filename = function() paste0("bayfront_plan_", Sys.Date(), ".csv"),
    content = function(file)
      write.csv(plan_export(), file, row.names = FALSE, na = "")
  )
}

shinyApp(ui, server)
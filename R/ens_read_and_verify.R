#' Read forecast and observations and verify.
#'
#' This is a wrapper for the verification process. Forecasts and observations
#' are read in, filtered down to common cases, errors checked, and a full
#' verification is done for all scores. To minimise memory usage, the
#' verification can be done for one lead time at time. It would also be possible
#' to parallelise the process using for example \link[parallel]{mclapply}, or
#' \link[furrr]{future_map}.
#'
#' @param start_date Start date to for the verification. Should be numeric or
#'   character. YYYYMMDD(HH)(mm).
#' @param end_date End date for the verification. Should be numeric or
#'   character.
#' @param parameter The parameter to verify.
#' @param fcst_model The forecast model(s) to verify. Can be a single string or
#'   a character vector of model names.
#' @param fcst_path The path to the forecast FCTABLE files.
#' @param obs_path The path to the observation OBSTABLE files.
#' @param lead_time The lead times to verify.
#' @param num_iterations The number of iterations per verification calculation.
#'   The default is to do the same number of iterations as there are lead times.
#'   If a small number of iterations is set, it may be useful to set
#'   \code{show_progress = TRUE}. The higher the number of iterations, the
#'   smaller the amount of data that is held in memory at any one time.
#' @param verify_members Whether to verify the individual members of the
#'   ensemble. Even if thresholds are supplied, only summary scores are
#'   computed. If you wish to compute categorical scores, the separate
#'   \link[harpPoint]{det_verify} function must be used.
#' @param thresholds The thresholds to compute categorical scores for.
#' @param members The members to retrieve if reading an EPS forecast. To select
#'   the same members for all forecast models, this should be a numeric vector.
#'   For specific members from specific models a named list with each element
#'   having the name of the forecast model and containing a a numeric vector.
#'   e.g. \cr \code{members = list(eps_model1 = seq(0, 3), eps_model2 = c(2,
#'   3))}. \cr For multi model ensembles, each element of this named list should
#'   contain another named list with sub model name followed by the desired
#'   members, e.g. \cr \code{members = list(eps_model1 = list(sub_model1 =
#'   seq(0, 3), sub_model2 = c(2, 3)))}
#' @param obsfile_template The template for OBSTABLE files - the default is
#'   "obstable", which is \code{OBSTABLE_{YYYY}.sqlite}.
#' @param groupings The groups to verify for. The default is "leadtime". Another
#'   common grouping might be \code{groupings = c("leadtime", "fcst_cycle")}.
#' @param by The frequency of forecast cycles to verify.
#' @param climatology The climatology to use for the Brier Skill Score. Can be
#'   "sample" for the sample climatology (the default), a named list with
#'   elements eps_model and member to use a member of an eps model in the
#'   harp_fcst object for the climatology, or a data frame with columns for
#'   threshold and climatology and also optionally leadtime.
#' @param stations The stations to verify for. The default is to use all
#'   stations from \link[harpIO]{station_list} that are common to all
#'   \code{fcst_model} domains.
#' @param jitter_fcst A function to perturb the forecast values by. This is used
#'   to account for observation error in the rank histogram. For other
#'   statistics it is likely to make little difference since it is expected that
#'   the observations will have a mean error of zero.
#' @param gross_error_check Logical of whether to perform a gross error check.
#' @param min_allowed The minimum value of observation to allow in the gross
#'   error check. If set to NULL the default value for the parameter is used.
#' @param max_allowed The maximum value of observation to allow in the gross
#'   error check. If set to NULL the default value for the parameter is used.
#' @param num_sd_allowed The number of standard deviations of the forecast that
#'   the obseravtions should be within. Set to NULL for automotic value
#'   depeninding on parameter.
#' @param show_progress Logical - whether to show a progress bar. Defaults to
#'   FALSE.
#' @param verif_path If set, verification files will be saved to this path.
#' @param fctable_file_template The template for the file names of the files to be read
#'   from. This would normally be one of the "fctable_*" templates that can be
#'   seen in \link{show_file_templates}. Can be a single string, a
#'   character vector or list of the same length as \code{fcst_model}. If not
#'   named, the order of templates is assumed to be the same as in
#'   \code{fcst_model}. If named, the names must match the entries in
#'   \code{fcst_model}.
#' @param lags
#' @param lag_fcst_models
#' @param parent_cycles
#' @param lag_direction
#' @param fcst_shifts
#' @param keep_unshifted
#' @param drop_neg_leadtimes
#' @param scale_fcst
#' @param scale_obs
#' @param common_cases_only
#' @param check_obs_fcst
#' @param vertical_coordinate
#' @param merge_lags_on_read
#'
#' @return A list containting two data frames: \code{ens_summary_scores} and
#'   \code{ens_threshold_scores}.
#' @export
#'
#' @examples
ens_read_and_verify <- function(
  start_date,
  end_date,
  parameter,
  fcst_model,
  fcst_path,
  obs_path,
  lead_time              = seq(0, 48, 3),
  num_iterations         = length(lead_time),
  verify_members         = TRUE,
  thresholds             = NULL,
  members                = NULL,
  vertical_coordinate    = c(NA_character_, "pressure", "model", "height"),
  fctable_file_template  = "fctable_eps",
  obsfile_template       = "obstable",
  groupings              = "leadtime",
  by                     = "6h",
  lags                   = "0s",
  merge_lags_on_read     = TRUE,
  lag_fcst_models        = NULL,
  parent_cycles          = NULL,
  lag_direction          = 1,
  fcst_shifts            = NULL,
  keep_unshifted         = FALSE,
  drop_neg_leadtimes     = TRUE,
  climatology            = "sample",
  stations               = NULL,
  scale_fcst             = NULL,
  scale_obs              = NULL,
  jitter_fcst            = NULL,
  common_cases_only      = TRUE,
  common_cases_xtra_cols = NULL,
  check_obs_fcst         = TRUE,
  gross_error_check      = TRUE,
  min_allowed            = NULL,
  max_allowed            = NULL,
  num_sd_allowed         = NULL,
  show_progress          = FALSE,
  verif_path             = NULL
) {

  first_obs <- start_date
  last_obs  <- (suppressMessages(harpIO::str_datetime_to_unixtime(end_date)) + 3600 * max(lead_time)) %>%
    harpIO::unixtime_to_str_datetime(harpIO::YMDhm)

  vertical_coordinate <- match.arg(vertical_coordinate)

  obs_data <- harpIO::read_point_obs(
    start_date          = first_obs,
    end_date            = last_obs,
    parameter           = parameter,
    obs_path            = obs_path,
    obsfile_template    = obsfile_template,
    gross_error_check   = gross_error_check,
    min_allowed         = min_allowed,
    max_allowed         = max_allowed,
    stations            = stations,
    vertical_coordinate = vertical_coordinate
  )

  parameter_sym <- rlang::sym(parameter)

  if (!is.null(scale_obs)) {
    stopifnot(is.list(scale_obs))
    check_scale_data(scale_obs, "obs")
    obs_data <- do.call(
      scale_point_obs,
      c(list(.obs = obs_data, parameter = parameter_sym), scale_obs)
    )
  }

  verif_data     <- list()

  if (num_iterations > length(lead_time)) {
    num_iterations <- length(lead_time)
  }

  lead_list <- split(lead_time, sort(seq_along(lead_time) %% num_iterations))

  stations_used <- list()
  for (i in 1:num_iterations) {

    cat("Lead time:", lead_list[[i]], "( Iteration", i, "of", num_iterations, ")\n")
    cat(rep("=", 80), "\n", sep = "")

    harp_parameter <- harpIO::parse_harp_parameter(
      parameter,
      vertical_coordinate = vertical_coordinate
    )

    if (harp_parameter$accum > 0 && lead_list[[i]] * 3600 < harp_parameter$accum) {
      warning_message <- paste0(
        "Cannot accumulate ",
        harpIO:::parse_accum(harp_parameter),
        harp_parameter$acc_unit,
        " ",
        harp_parameter$basename,
        " for lead time: ",
        lead_list[[i]],
        "h. Skipping to next iteration."
      )
      warning(warning_message, call. = FALSE, immediate. = TRUE)
      next()
    }

    if (length(lags) == 1 && is.null(names(lags))) {
      lags <- rep(lags, length(fcst_model)) %>%
        as.list() %>%
        purrr::set_names(fcst_model)
    }

    if (!is.null(fcst_shifts)) {
      if (keep_unshifted) {
        if (!any(grepl("_unshifted$", names(lags)))) {
          unshifted_names       <- paste0(names(fcst_shifts), "_unshifted")
          fcst_model            <- c(fcst_model, unshifted_names)
          lags[unshifted_names] <- lags[names(fcst_shifts)]
          if (!is.null(scale_fcst)) {
            shifted_and_scaled <- intersect(names(scale_fcst), names(fcst_shifts))
            if (length(shifted_and_scaled) > 0) {
              scale_fcst[paste0(shifted_and_scaled, "_unshifted")] <- scale_fcst[shifted_and_scaled]
            }
          }
          if (!is.null(members)) {
            shifted_and_select_members <- intersect(names(members), names(fcst_shifts))
            if (length(shifted_and_select_members) > 0) {
              members[paste0(shifted_and_select_members, "_unshifted")] <- members[shifted_and_select_members]
            }
          }
          if (!is.null(names(fctable_file_template))) {
            shifted_and_template <- intersect(names(fctable_file_template), names(fcst_shifts))
            if (length(shifted_and_template) > 0) {
              fctable_file_template[paste0(shifted_and_template, "_unshifted")] <- fctable_file_template[shifted_and_template]
            }
          }
        }
      }
      lags[names(fcst_shifts)] <- lapply(fcst_shifts, paste0, "h")
    }

    fcst_data <- harpIO::read_point_forecast(
      start_date          = start_date,
      end_date            = end_date,
      fcst_model          = fcst_model,
      fcst_type           = "EPS",
      parameter           = parameter,
      lead_time           = lead_list[[i]],
      lags                = lags,
      merge_lags          = merge_lags_on_read,
      by                  = by,
      file_path           = fcst_path,
      stations            = stations,
      members             = members,
      file_template       = fctable_file_template,
      vertical_coordinate = vertical_coordinate
    ) %>%
      merge_multimodel()

    if (!is.null(scale_fcst)) {
      stopifnot(is.list(scale_fcst))
      if (is.null(names(scale_fcst))) {
        if (length(scale_fcst) == 1 && length(fcst_model) > 1) {
          warning("Only one scaling given in 'scale_fcst'. Applying scaling to all elements of 'fcst_model'.", immediate. = TRUE, call. = FALSE)
          scale_fcst <- rep(scale_fcst, length(fcst_model)) %>%
            purrr::set_names(fcst_model)
        } else if (length(scale_fcst) == length(fcst_model)) {
          warning("No names given in 'scale_fcst'. Assuming same order as elements of 'fcst_model'.", immediate. = TRUE, call. = FALSE)
          names(scale_fcst) <- fcst_model
        } else {
          stop("'scale_fcst' must be a named list with names as in 'fcst_model'.", call. = FALSE)
        }
      } else {
        bad_names <- setdiff(names(scale_fcst), fcst_model)
        if (length(bad_names) > 0) {
          stop(paste(bad_names, collapse = ", "), "supplied in 'scale_fcst', but do not exist in 'fcst_model'.", call. = FALSE)
        }
      }
      purrr::walk(scale_fcst, check_scale_data, "fcst")
      fcst_data[names(scale_fcst)] <- purrr::map2(
        fcst_data[names(scale_fcst)],
        scale_fcst,
        ~ do.call(scale_point_forecast, c(list(.fcst = .x), .y))
      )
    }

    if (!merge_lags_on_read) {
      if (!is.null(lag_fcst_models)) {
        if (is.null(parent_cycles)) {
          stop("'parent_cycles' must be passed as well as 'lag_fcst_models'.")
        }
        fcst_data <- lag_forecast(
          fcst_data,
          lag_fcst_models,
          parent_cycles,
          direction = lag_direction
        )
      }
    }

    if (!is.null(fcst_shifts)) {
      if (merge_lags_on_read) {
        shifted_models <- names(fcst_data)[names(fcst_data) %in% names(fcst_shifts)]
        names(fcst_data)[names(fcst_data) %in% names(fcst_shifts)] <- paste(
          shifted_models,
          "shifted",
          paste0(fcst_shifts, "h"),
          sep = "_"
        )
      } else {
        fcst_data <- shift_forecast(
          fcst_data,
          fcst_shifts,
          keep_unshifted           = FALSE,
          drop_negative_lead_times = drop_neg_leadtimes
        )
      }
    }

    fcst_data <- fcst_data %>%
      dplyr::filter(.data$leadtime %in% lead_list[[i]])

    if (common_cases_only) {
      col_names    <- unique(unlist(lapply(fcst_data, colnames)))
      xtra_cols_err <- paste("common_cases_xtra_cols must be wrapped in vars and unquoted,\n",
        "e.g. common_cases_xtra_cols = vars(p).")
      xtra_cols_null <- try(is.null(common_cases_xtra_cols), silent = TRUE)
      if (inherits(xtra_cols_null, "try-error")) {
        stop(xtra_cols_err, call. = FALSE)
      } else {
        if (xtra_cols_null) {
          fcst_data <- common_cases(fcst_data)
        } else {
          if (inherits(common_cases_xtra_cols, "quosures")) {
            xtra_cols <- purrr::map_chr(rlang::eval_tidy(common_cases_xtra_cols), rlang::quo_name)
            if (length(setdiff(xtra_cols, col_names)) > 1) {
              stop(
                "Column(s) '", paste(setdiff(xtra_cols, col_names), collapse = "','"), "' ",
                "for selecting common cases not found.",
                call. = FALSE
              )
            } else {
              fcst_data <- common_cases(fcst_data, !!!common_cases_xtra_cols)
            }
          } else {
            stop(xtra_cols_err, call. = FALSE)
          }
        }
      }
    }

    if (all(sapply(fcst_data, nrow)) < 1) {
      message("No forecast data available. Skipping to next iteration.")
      next()
    }

    # Check column names for parameter - if not found, try the base name
    if (!is.element(harp_parameter[["fullname"]], colnames(obs_data))) {
      if (is.element(harp_parameter[["basename"]], colnames(obs_data))) {
        names(obs_data)[names(obs_data) == harp_parameter[["basename"]]] <- harp_parameter[["fullname"]]
      } else {
        stop("Don't know what to do with parameter '", harp_parameter[["fullname"]], "'.", call. = FALSE)
      }
    }

    fcst_data <- join_to_fcst(fcst_data, obs_data)
    stations_used[[i]] <- unique(unlist(dplyr::pull(fcst_data, .data[["SID"]])))

    if (any(purrr::map_int(fcst_data, nrow) == 0)) next()

    if (check_obs_fcst) {
      fcst_data <- check_obs_against_fcst(fcst_data, !! parameter_sym, num_sd_allowed = num_sd_allowed)
    }

    if (any(purrr::map_int(fcst_data, nrow) == 0)) next()

    verif_data[[i]] <- ens_verify(
      fcst_data,
      !! parameter_sym,
      verify_members = verify_members,
      thresholds     = thresholds,
      groupings      = groupings,
      jitter_fcst    = jitter_fcst,
      climatology    = climatology,
      show_progress  = show_progress
    )

  } # end loop over lead times

  verif_data <- verif_data[purrr::map_lgl(verif_data, ~!is.null(.x))]

  if (length(verif_data) < 1) {
    stop("No data to verify", call. = FALSE)
  }

  stations_used <- unique(unlist(stations_used))

  verif_data       <- bind_point_verif(verif_data)
  verif_attributes <- attributes(verif_data)

  verif_data <- purrr::map(
    verif_data,
    ~ dplyr::mutate(
      .x,
      mname = case_when(
        grepl("_unshifted$", .data$mname) ~ gsub("_unshifted", "", .data$mname),
        TRUE                             ~ .data$mname
      )
    )
  )

  attributes(verif_data)           <- verif_attributes
  attr(verif_data, "num_stations") <- as.character(length(stations_used))
  attr(verif_data, "stations")     <- sort(stations_used)

  if (!is.null(verif_path)) {
    harpIO::save_point_verif(verif_data, verif_path = verif_path)
  }

  verif_data

}

check_scale_data <- function(scale_data, scale_what) {
  expected_args <- sort(c("scale_factor", "new_units", "multiplicative"))
  ref_function <- ifelse(scale_what == "obs", "'scale_point_obs'", "'scale_point_forecast'")
  text_start   <- ifelse(scale_what == "obs", "'scale_obs'", "Elements of 'scale_point_forecast'")
  if (!identical(sort(names(scale_data)), sort(expected_args))) {
    stop(
      text_start, " must be a named list with names scale_factor, new_units and multiplicative\n",
      "See ", ref_function, " for more details.",
      call. = FALSE
    )
  }

}

#' Calculate the fatigue given a vector x
#'
#' @param x A numeric vector containing inter tap intevals
#' @return A list containing fatigue10, fatigue25, fatigue50 where
#' fatigueX is the difference in the mean values of the
#' first X percent of input x and last X percent of input x
fatigue <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  top10 <- round(0.1 * n)
  top25 <- round(0.25 * n)
  top50 <- floor(0.5 * n)
  return(list(fatigue10 = mean(x[1:top10]) - mean(x[(n - top10):n]),
              fatigue25 = mean(x[1:top25]) - mean(x[(n - top25):n]),
              fatigue50 = mean(x[1:top50]) - mean(x[(n - top50):n])))
}

#' Calculate the drift given x and y
#'
#' @param x A vecor containing x co-ordinates (same length as that of y)
#' @param y A vecor containing y co-ordinates (same length as that of x)
#' @return Drift vector which is sqrt(dx^2 + dy^2)
calculate_drift <- function(x, y) {
  dx <- diff(x, lag = 1)
  dy <- diff(y, lag = 1)
  return(sqrt(dx^2 + dy^2))
}

#' Calculate the Mean Teager-Kaiser energy,
#' adapted from TKEO function in library(seewave) using f = 1, m = 1, M = 1
#'
#' @param x A vector x whose Mean Taiger-Kaiser Energy Operator value
#' needs to be calculated
#' @return A numeric value that is representative of the MeanTKEO
mean_tkeo <- function(x) {
  x <- x[!is.na(x)] # Remove NAs
  y <- x^2 - c(x[-1], NA) * c(NA, x[1:(length(x) - 1)])
  return(mean(y, na.rm = TRUE))
}

#' Calculate the Coefficient of Variation (coef_var) for a given sequence
#'
#' @param x A numeric vector
#' @return A numeric value that is representative of the Coefficient of Variation
coef_var <- function(x) {
  x <- x[!is.na(x)] # Remove NAs
  return((sd(x) / mean(x)) * 100)
}

#' Curate the raw tapping data to get Left and Right events,
#' after applying the threshold.
#'
#' @param tap_data A dataframe with t,x,y and buttonid columns
#' @param depress_threshold The threshold for intertap distance
#' @return A dataframe with feature values and the appropriate error message
get_left_right_events_and_tap_intervals <- function(tap_data,
                                                    depress_threshold = 20) {
  tap_time <- tap_data$t - tap_data$t[1]
  ## calculate X offset
  tap_x <- tap_data$x - mean(tap_data$x)
  ## find left/right finger 'depress' event
  dx <- diff(tap_x)
  i <- c(1, which(abs(dx) > depress_threshold) + 1)
  ## filter data
  tap_data <- tap_data[i, ]
  tap_time <- tap_time[i]
  ## find depress event intervals
  tap_intervals <- diff(tap_time)
  ### ERROR CHECK -
  if (nrow(tap_data) >= 5) {
    return(list(
      tap_data = tap_data,
      tap_intervals = tap_intervals,
      error = FALSE))
  } else {
    return(list(tap_data = NA, tap_intervals = NA, error = TRUE))
  }
}

#' Calculate the sampling rate.
#'
#' @param sensor_data A data frame with a time column \code{t}
#' @return The sampling rate (number of samples taken per second on average).
get_sampling_rate <- function(sensor_data) {
  tryCatch({
    t_length <- length(sensor_data$t)
    sampling_rate <-  t_length / (sensor_data$t[t_length] - sensor_data$t[1])
    return(sampling_rate)
  }, error = function(e) { NA })
}

#' Check if a dataframe has an error column with at least one value
#'
#' @param sensor_data A dataframe
#' @return logical
has_error <- function(sensor_data) {
  tibble::has_name(sensor_data, "error") && any(!is.na(sensor_data$error))
}

#' Gather the axial columns
#'
#' Gather x, y, and z columns into a single \code{axis} column and
#' normalize the \code{t} column to begin at \code{t} = 0.
#'
#' @param sensor_data A data frame with a time column \code{t},
#' and at least one additional axial column.
#' @return Sensor data in tidy format.
tidy_sensor_data <- function(sensor_data) {
  if (has_error(sensor_data)) return(sensor_data)
  if (any(is.na(sensor_data$t))) stop("NA values present in column t.")
  tidy_sensor_data <- tryCatch({
    t0 <- sensor_data$t[1]
    normalized_sensor_data <-  sensor_data %>% dplyr::mutate(t = t - t0)
    index <- order(sensor_data$t)
    tidy_sensor_data <- normalized_sensor_data[index, ] %>%
      tidyr::gather(axis, value, -t) %>%
      dplyr::group_by(axis)
  }, error = function(e) {
    dplyr::tibble(
      error = "Could not put sensor data in tidy format by gathering the axes.")
  })
  return(tidy_sensor_data)
}

#' Detrend time series data
#'
#' @param time Numeric vector containing the timestamp values.
#' @param values Numeric vector the same length as \code{time}.
#' @return Numeric vector with detrended values.
detrend <- function(time, values) {
  detrended_values <- loess(values ~ time)$residual
  return(detrended_values)
}

#' Detrend sensor data
#'
#' @param sensor_data A data frame with columns \code{t}, \code{value}.
#' @return Sensor data with detrended values.
mutate_detrend <- function(sensor_data) {
  if (has_error(sensor_data)) return(sensor_data)
  detrended_sensor_data <- tryCatch({
    detrended_sensor_data <- sensor_data %>%
      dplyr::mutate(value = detrend(t, value))
  }, error = function(e) {
    dplyr::tibble(error = "Detrend error")
  })
  return(detrended_sensor_data)
}

#' Apply a pass-band filter to time series data
#'
#' @param values Numeric vector.
#' @param window_length The number of samples per window during filtering.
#' @param sampling_rate Sampling rate of the values.
#' @param frequency_range Bounds on frequency in Hz
#' @return Filtered time series data
bandpass <- function(values, window_length, sampling_rate,
                     frequency_range) {
  frequency_low <- frequency_range[1]
  frequency_high <- frequency_range[2]
  if (frequency_low * 2 / sampling_rate > 1 ||
      frequency_high * 2 / sampling_rate > 1) {
    stop("Frequency parameters can be at most half the sampling rate.")
  } else if (any(is.na(values))) {
    stop("NA values present in input.")
  }
  bandpass_filter <- signal::fir1(
    window_length - 1,
    c(frequency_low * 2 / sampling_rate,
      frequency_high * 2 / sampling_rate),
    type = "pass",
    window = seewave::hamming.w(window_length))
  filtered_values <- signal::filtfilt(bandpass_filter, values)
  return(filtered_values)
}

#' Apply a pass-band filter to sensor data
#'
#' @param sensor_data A data frame with column \code{value}.
#' @param window_length The number of samples per window during filtering.
#' @param sampling_rate Sampling rate of the value column.
#' @param frequency_range Bounds on frequency in Hz
#' @return Filtered time series data
mutate_bandpass <- function(sensor_data, window_length, sampling_rate,
                            frequency_range) {
  if (has_error(sensor_data)) return(sensor_data)
  bandpass_filtered_sensor_data <- tryCatch({
    sensor_data %>%
      dplyr::mutate(value = bandpass(value, window_length,
                                     sampling_rate, frequency_range))
  }, error = function(e) {
    dplyr::tibble(error = "Bandpass filter error")
  })
  return(bandpass_filtered_sensor_data)
}

#' Select a specific time range from sensor data.
#'
#' @param sensor_data A data frame with a time column \code{t}.
#' @param t1 Start time.
#' @param t2 End time.
#' @return Sensor data between time t1 and t2 (inclusive)
filter_time <- function(sensor_data, t1, t2) {
  if (has_error(sensor_data)) return(sensor_data)
  if (!hasName(sensor_data, "t")) {
    stop("Input has no column t.")
  }
  filtered_time_sensor_data <- tryCatch({
    filtered_time_sensor_data <- sensor_data %>% dplyr::filter(t >= t1, t <= t2)
    if (nrow(filtered_time_sensor_data) == 0) {
      return(dplyr::tibble(error = "Not enough time samples"))
    }
    return(filtered_time_sensor_data)
  }, error = function(e) {
    dplyr::tibble(error = "Not enough time samples")
  })
}

#' Window the value vector of sensor data for each axis
#'
#' @param sensor_data A data frame with columns \code{t}, \code{axis}, \code{value}.
#' @param window_length The number of samples per window.
#' @param window_overlap Fraction in the interval [0, 1) specifying the amount of
#' window overlap.
#' @param window_name window name: bartlett, blackman, flattop, hamming,
#' hanning, or rectangle. See \code{\link[seewave]{ftwindow}}.
#' @return Windowed sensor data
window <- function(sensor_data, window_length, window_overlap,
                   window_name = "hamming") {
  if (has_error(sensor_data)) return(sensor_data)
  tryCatch({
    spread_sensor_data <- sensor_data %>%
      tidyr::spread(axis, value)
    windowed_sensor_data <- spread_sensor_data %>%
      dplyr::select(x, y, z) %>%
      purrr::map(window_signal,
                 window_length = window_length,
                 window_overlap = window_overlap,
                 window_name = window_name)
    tidy_windowed_sensor_data <- lapply(
      windowed_sensor_data,
      function(windowed_matrix) {
        tidy_tibble <- windowed_matrix %>%
          dplyr::as_tibble() %>%
          tidyr::gather(window, value, convert = T)
        return(tidy_tibble)
      }) %>%
      dplyr::bind_rows(.id = "axis")
    start_end_times <- window_start_end_times(spread_sensor_data$t,
                                              window_length = window_length,
                                              window_overlap = window_overlap)
    tidy_windowed_sensor_data <- tidy_windowed_sensor_data %>%
      dplyr::left_join(start_end_times, by = "window") %>%
      dplyr::select(axis, window, window_start_time,
                    window_end_time, value)
    return(tidy_windowed_sensor_data)
  }, error = function(e) {
    dplyr::tibble(error = "Windowing error")
  })
}

#' Compute start/end timestamps for each window
#'
#' @param t A numeric time vector
#' @param window_length The number of samples per window.
#' @param window_overlap Fraction in the interval [0, 1) specifying the amount of
#' window overlap.
#' @return A dataframe with columns window, window_start_time,
#' window_end_time, window_start_index, window_end_index
window_start_end_times <- function(t, window_length, window_overlap) {
  seq_length <- length(t)
  if (seq_length < window_length) {
    window_length <- seq_length
    window_overlap <- 1
  }
  if (window_overlap == 1) {
    start_indices <- 1
    end_indices <- window_length
  } else {
    window_step <- round(window_length * (1 - window_overlap))
    start_indices <- seq(1, seq_length, window_step)
    end_indices <- seq(window_length, seq_length, window_step)
  }
  start_indices <- start_indices[1:length(end_indices)]
  start_times <- t[start_indices]
  end_times <- t[end_indices]
  window_start_end_times <- dplyr::tibble(
    window = seq(1, length(start_indices)),
    window_start_time = start_times,
    window_end_time = end_times,
    window_start_index = start_indices,
    window_end_index = end_indices)
  return(window_start_end_times)
}

#' Window a signal
#'
#' Given a numeric vector, this function will return its windowed signal.
#'
#' @param values Timeseries vector of length n.
#' @param window_length The number of samples per window.
#' @param window_overlap Fraction in the interval [0, 1) specifying the amount of
#' window overlap.
#' @param window_name window name: bartlett, blackman, flattop, hamming,
#' hanning, or rectangle. See \code{\link[seewave]{ftwindow}}.
#' @return A matrix of window_length x nwindows
window_signal <- function(values, window_length = 256,
                          window_overlap = 0.5, window_name = "hamming") {
  start_end_times <- window_start_end_times(
    values, window_length = window_length, window_overlap = window_overlap)
  nstart <- start_end_times$window_start_index
  nend <- start_end_times$window_end_index
  window <- seewave::ftwindow(window_length, wn = window_name)
  windowed_signal <- purrr::map2(
    nstart, nend, ~ values[seq(.x, .y)] * window) %>%
    simplify2array()
  colnames(windowed_signal) <- 1:dim(windowed_signal)[2]
  return(windowed_signal)
}

#' Take the derivative of a vector v
#'
#' Take the derivative of a vector v by calculating the difference
#' between component x_i and x_(i-1).
#'
#' @param v A numeric vector
#' @return A numeric vector
derivative <- function(v) {
  derivative <- (v - dplyr::lag(v))
  derivative[1] <- 0
  return(derivative)
}

#' Take the integral of a vector v
#'
#' Take the integral of a vector v by computing the inverse of
#' the lagged differences (\code{diff} function).
#'
#' @param v A numeric vector
#' @return The integral of \code{v} as a numeric vector.
integral <- function(v) {
  integral <- diffinv(v)[-1]
  return(integral)
}

#' Add a column which is the "derivative" of an existing column
#' to a time-series dataframe.
#'
#' See function \code{derivative}.
#'
#' @param sensor_data A data frame with column \code{col}.
#' @param sampling_rate Sampling rate of \code{col}.
#' @param col Name of column to differentiate.
#' @param derived_col Name of new column which is the derivative of \code{col}.
#' @return A dataframe
mutate_derivative <- function(sensor_data, sampling_rate, col, derived_col) {
  if (has_error(sensor_data)) return(sensor_data)
  sensor_data_with_derivative <- tryCatch({
    sensor_data %>%
      dplyr::mutate(!!derived_col := derivative(!!dplyr::sym(col)) * sampling_rate)
  }, error = function(e) {
    dplyr::tibble(error = paste("Error calculating", derived_col))
  })
  return(sensor_data_with_derivative)
}

#' Add a column which is the "integral" of an existing column
#' to a time-series dataframe.
#'
#' See function \code{integral}.
#'
#' @param sensor_data A data frame with column \code{col}.
#' @param sampling_rate Sampling rate of \code{col}.
#' @param col Name of column to integrate.
#' @param derived_col Name of new column which is the integral of \code{col}.
#' @return A dataframe
mutate_integral <- function(sensor_data, sampling_rate, col, derived_col) {
  if (has_error(sensor_data)) return(sensor_data)
  sensor_data_with_integral <- tryCatch({
    sensor_data %>%
      dplyr::mutate(!!derived_col := integral(!!dplyr::sym(col)) * sampling_rate)
  }, error = function(e) {
    dplyr::tibble(error = paste("Error calculating", derived_col))
  })
  return(sensor_data_with_integral)
}

#' Construct a dataframe with ACF values
#'
#' @param sensor_data A data frame with column \code{col}.
#' @param col Name of column to calculate acf of.
#' @param lag_max See \code{\link[stats]{acf}}
#' @return A data frame with an acf column.
mutate_acf <- function(sensor_data, col, lag_max = NULL) {
  if (has_error(sensor_data)) return(sensor_data)
  acf_data <- tryCatch({
    sensor_data %>%
      dplyr::mutate(acf = acf(.[[col]], plot = F, lag.max = lag_max)$acf[-1])
  }, error = function(e) {
    dplyr::tibble(error = "Error calculating ACF")
  })
  return(acf_data)
}

#' Get min and max gravity values for each window
#'
#' @param gravity_vector A gravity vector
#' @param window_length The number of samples per window.
#' @param window_overlap Fraction in the interval [0, 1) specifying the amount of
#' window overlap during the windowing transformation.
#' @return Min and max values for each window.
tag_outlier_windows_ <- function(gravity_vector, window_length, window_overlap) {
  if (!is.vector(gravity_vector)) stop("Input must be a numeric vector")
  gravity_summary <- gravity_vector %>%
    window_signal(window_length = window_length,
                  window_overlap = window_overlap,
                  window_name = "rectangle") %>%
    dplyr::as_tibble() %>%
    tidyr::gather(window, value) %>%
    dplyr::group_by(window) %>%
    dplyr::summarise(max = max(value, na.rm = F),
                     min = min(value, na.rm = F))
  return(gravity_summary)
}

#' Identify abnormal device rotations
#'
#' Identify windows in which the phone may have been rotated or flipped,
#' as indicated by a gravity vector
#'
#' @param gravity A dataframe with gravity vectors for columns
#' @param window_length The number of samples per window.
#' @param window_overlap Fraction in the interval [0, 1) specifying the amount of
#' window overlap during the windowing transformation.
#' @return Rotations errors for each window.
tag_outlier_windows <- function(gravity, window_length, window_overlap) {
  gr_error <- tryCatch({
    gr_error <- gravity %>%
      purrr::map(tag_outlier_windows_, window_length, window_overlap) %>%
      dplyr::bind_rows(.id = "axis") %>%
      dplyr::mutate(error = sign(max) != sign(min)) %>%
      dplyr::group_by(window) %>%
      dplyr::summarise(error = any(error, na.rm = T)) %>%
      dplyr::mutate(window = as.integer(window))
    gr_error$error[gr_error$error == TRUE] <- "Phone rotated within window"
    gr_error$error[gr_error$error == FALSE] <- "None"
    return(gr_error)
  }, error = function(e) {
    dplyr::tibble(error = "Error tagging outlier windows")
  })
  return(gr_error)
}

#' Get default tapping features
#'
#' Calculates features characterising tapping data
#' (interaction terms etc., from the tap data frame)
#'
#' @param tap_data A data frame with columns t, x, y, buttonid containing
#' tapping measurements. buttonid can be from
#' c('TappedButtonLeft','TappedButtonRight','TappedButtonNone')
#' indicating a tap that has been classified as to the
#' left, right or neither of those places on the screen
#' @return A features data frame of dimension 1 x n_features
tap_data_summary_features <- function(tap_data) {
  features <- tryCatch({
    dplyr::tibble(
      numberTaps = nrow(tap_data),
      buttonNoneFreq = sum(
        tap_data$buttonid == "TappedButtonNone") / nrow(tap_data),
      corXY = cor(tap_data$x, tap_data$y, use = "p"),
      error = "None")
  },
  error = function(x) {
    return(dplyr::tibble(
      error = "Error calculating tap data(frame) summary features"))
  })
}

#' Get default tapping features for intertap distance
#'
#' Calculates features characterising a timeseries data
#'
#' @param tap_intervals A numeric vector containing intertap intervals
#' @return A features data frame of dimension 1 x n_features
intertap_summary_features <- function(tap_intervals) {
  tap_intervals <- tap_intervals %>% na.omit()
  # determine Autocorrelation
  aux_acf <- tryCatch({
    acf(tap_intervals, lag.max = 2, plot = FALSE)$acf
  }, error = function(x) {
    return(list(NA, NA, NA))
  })
  aux_fatigue <- fatigue(tap_intervals)
  features <- tryCatch({
    dplyr::tibble(mean = mean(tap_intervals, na.rm = TRUE),
                  median = median(tap_intervals, na.rm = TRUE),
                  iqr = IQR(tap_intervals, type = 7, na.rm = TRUE),
                  min = min(tap_intervals, na.rm = TRUE),
                  max = max(tap_intervals, na.rm = TRUE),
                  skew = e1071::skewness(tap_intervals),
                  kur = e1071::kurtosis(tap_intervals),
                  sd = sd(tap_intervals, na.rm = TRUE),
                  mad = mad(tap_intervals, na.rm = TRUE),
                  cv = coef_var(tap_intervals),
                  range = diff(range(tap_intervals, na.rm = TRUE)),
                  tkeo = mean_tkeo(tap_intervals),
                  ar1 = aux_acf[[2]],
                  ar2 = aux_acf[[3]],
                  fatigue10 = aux_fatigue[[1]],
                  fatigue25 = aux_fatigue[[2]],
                  fatigue50 = aux_fatigue[[3]],
                  error = "None")
  }, error = function(x) {
    return(dplyr::tibble(error = "Error Calculating intertap summary features"))
  })
  return(features)
}

#' Get default tapping features for tap drift
#'
#' Calculates features characterising a timeseries data
#'
#' @param tap_drift A numeric vector
#' @return A features data frame of dimension 1 x n_features
tapdrift_summary_features <- function(tap_drift) {
  tap_drift <- tap_drift %>% na.omit()
  features <- tryCatch({
    dplyr::tibble(mean = mean(tap_drift, na.rm = TRUE),
                  median = median(tap_drift, na.rm = TRUE),
                  iqr = IQR(tap_drift, type = 7, na.rm = TRUE),
                  min = min(tap_drift, na.rm = TRUE),
                  max = max(tap_drift, na.rm = TRUE),
                  skew = e1071::skewness(tap_drift),
                  kur = e1071::kurtosis(tap_drift),
                  sd = sd(tap_drift, na.rm = TRUE),
                  mad = mad(tap_drift, na.rm = TRUE),
                  cv = coef_var(tap_drift),
                  range = diff(range(tap_drift, na.rm = TRUE)),
                  error = "None")
  },
  error = function(x){
    return(dplyr::tibble(error = "Error Calculating tapdrift summary features"))
  })
  return(features)
}


#' Get AR spectrum
#'
#' Given a numeric vector, this function will return a spectrum
#' with all pole AR model.
#'
#' @param values A timeseries vector.
#' @param sampling_rate Sampling rate of the signal (by default it is 100 Hz).
#' @param nfreq Number of frequecy points to be interpolated.
#' @return An AR spectrum.
get_spectrum <- function(values, sampling_rate = 100, nfreq = 500){
  tmp <- stats::spec.ar(values, n.freq = nfreq, plot = F)
  spectrum <- data.frame(freq = tmp$freq * sampling_rate, pdf = tmp$spec)
  return(spectrum)
}


#' Get EWT spectrum
#'
#' Given the spectrum of a time series vector this function will return its
#' Empirical Wavelet Transformed spectrum.
#'
#' @param spectrum FFT spectrum as a two dimensional data frame with columns
#' names as freq and pdf respectively n.freq x 2.
#' @param npeaks Number of peaks to be captured.
#' @param fraction_min_peak_height Minimum height (relative to maximum peak height)
#' a peak has to have. Specified as fraction between 0 and 1.
#' @param min_peak_distance The minimum distance (in indices) peaks.
#' have to have to be counted.
#' @param sampling_rate Sampling rate of the signal (by default it is 100 Hz).
#' @return Emprical wavelet transformed spectrum of dimension n.freq x (npeaks + 1).
get_ewt_spectrum <- function(spectrum, npeaks = 3,
                             fraction_min_peak_height = 0.1,
                             min_peak_distance = 1, sampling_rate = 100) {
  # Find top peaks for EWT calculation
  peak_freqs <- pracma::findpeaks(spectrum$pdf,
                                  minpeakheight = fraction_min_peak_height *
                                  max(spectrum$pdf, na.rm = T),
                                  minpeakdistance = min_peak_distance,
                                  npeaks = npeaks,
                                  sortstr = TRUE)

  # Convert peak frequency to radians and find mid points
  peak_freqs <- spectrum$freq[suppressWarnings(
    sort(peak_freqs[, 2]))] * pi * 2 / sampling_rate
  peak_freqs <- unique(c(0, peak_freqs, pi))
  mid_peak_freqs <- c(0, peak_freqs[-length(peak_freqs)] + diff(peak_freqs) / 2, pi)

  # Choose optimal scaling operator for the transition widths
  numerator_vec <- mid_peak_freqs[2:(length(mid_peak_freqs) + 2)] -
    mid_peak_freqs[1:(length(mid_peak_freqs) + 1)]
  denominator_vec <- mid_peak_freqs[2:(length(mid_peak_freqs) + 2)] +
    mid_peak_freqs[1:(length(mid_peak_freqs) + 1)]
  optimal_gamma <- min(numerator_vec / denominator_vec, na.rm = TRUE)

  # Compute emprical scaling and wavelets
  empirical_wavelets <- purrr::map2(
    mid_peak_freqs[1:(length(mid_peak_freqs) - 1)],
    mid_peak_freqs[2:length(mid_peak_freqs)],
    .f = function(wn1, wn2, n.freq, optimal_gamma) {
      # Compute emprical scaling function for the first peak
      phi.sy <- rep(0, n.freq)
      w <- seq(0, pi, len = n.freq)

      # Check to see if wn1 is 0, to avoid dividing by 0
      if(wn1 == 0){
        wn1 = 0.00001
      }

      # Compute beta (an arbitary coefficient)
      x <- (1 / (2 * optimal_gamma * wn1)) * (abs(w) - (1 - optimal_gamma) * wn1)
      beta1 <- x^4 * (35 - 84 * x + 70 * x^2 - 20 * x^3)

      x <- (1 / (2 * optimal_gamma * wn2)) * (abs(w) - (1 - optimal_gamma) * wn2)
      beta2 <- x^4 * (35 - 84 * x + 70 * x^2 - 20 * x^3)

      if (wn2 != pi) {
        # Compute scaling/wavelets for different conditions
        ind <- ((1 + optimal_gamma) * wn1 <= abs(w)) &
                (abs(w) <= (1 - optimal_gamma) * wn2)
        phi.sy[ind] <- 1
        ind <- ((1 - optimal_gamma) * wn2 <= abs(w)) &
          (abs(w) <= (1 + optimal_gamma) * wn2)
        phi.sy[ind] <- cos(pi * beta2[ind] / 2)
        ind <- ((1 - optimal_gamma) * wn1 <= abs(w)) &
          (abs(w) <= (1 + optimal_gamma) * wn1)
        phi.sy[ind] <- sin(pi * beta1[ind] / 2)
      } else {
        # Compute scaling/wavelets for different conditions
        ind <- abs(w) <= (1 - optimal_gamma) * wn1
        phi.sy[ind] <- 1
        ind <- ((1 - optimal_gamma) * wn1 <= abs(w)) &
          (abs(w) <= (1 + optimal_gamma) * wn1)
        phi.sy[ind] <- cos(pi * beta1[ind] / 2)
        phi.sy <- 1 - phi.sy
      }
      return(phi.sy)
    },
    dim(spectrum)[1], optimal_gamma)

  # Compute EW modified spectrumrum
  ew_spectrum <- sapply(empirical_wavelets,
                        function(x, spectrum) {spectrum$pdf * x}, spectrum)

  return(ew_spectrum)
}

#' Map a function to a single column within tibble groups
#'
#' A convenience function for mapping a function -- which accepts a
#' vector as input and outputs an atomic value -- to a single column
#' of a dataframe. If the dataframe is grouped, the function will be
#' applied within each group.
#'
#' @param x A tibble
#' @param col Column to pass as a vector to \code{f}.
#' @param f Function to be mapped to \code{col}.
#' @param ... Additional arguments to \code{f}.
#' @return A dataframe with the original grouped columns (if \code{x} had
#' originally been grouped) and a \code{data} column containing
#' the output of the mapped function \code{f}.
map_groups <- function(x, col, f, ...) {
  dots <- rlang::enquos(...) # can also use enexprs()
  x %>%
    tidyr::nest() %>%
    dplyr::mutate(data = purrr::map(data, ~ f(.[[col]], !!!dots))) %>%
    tidyr::unnest(data)
}

#' Extract features from a column
#'
#' Apply each of the functions in \code{funs} to the column
#' \code{col} in the grouped data frame \code{x}. Each of the functions in
#' \code{funs} must accept a single vector as input and output
#' a data frame.
#'
#' @param x A grouped data frame with column \code{col}.
#' @param col The name of the column in \code{x} to pass to each
#' function in \code{funs}.
#' @param funs A list of functions that each accept a single vector as input.
#' @return a data frame with the original grouped columns and
#' other feature columns.
extract_features <- function(x, col, funs) {
  groups <- dplyr::group_vars(x)
  funs_output <- purrr::map(
    funs, ~ map_groups(
      x = x,
      col = col,
      f = .))
  if (length(groups)) { # concatenate elements of funs_output
    funs_output <- funs_output %>%
      purrr::reduce(dplyr::left_join, by = groups) %>%
      dplyr::mutate(measurementType = col) %>%
      dplyr::select(measurementType, dplyr::one_of(groups), dplyr::everything())
  }
  return(funs_output)
}
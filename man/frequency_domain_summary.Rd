% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/feature_extraction_functions.R
\name{frequency_domain_summary}
\alias{frequency_domain_summary}
\title{Returns statistical summary of the frequency spectrum}
\usage{
frequency_domain_summary(values, sampling_rate = NA, npeaks = NA)
}
\arguments{
\item{values}{A numeric vector from a time series measurement.}

\item{sampling_rate}{Sampling_rate of \code{values}. If NA it uses default
sampling rate of 100Hz.}

\item{npeaks}{Number of peaks to be computed in emprical wavelet transformation (EWT).
If NA it uses the default value of 3.}
}
\value{
A features data frame of dimension 1 x 19. See the
feature definition vignette:
\code{vignette("feature_definitions", package="mhealthtools")}
}
\description{
A convenience feature extraction function that characterises the
frequency spectrum of a given time series in to statistical features
in the frequency domain.
}
\examples{
frequency_features = frequency_domain_summary(
  accelerometer_data$x,
  sampling_rate = 100.122,
  npeaks = 3)
}
\author{
Thanneer Malai Perumal, Phil Snyder
}

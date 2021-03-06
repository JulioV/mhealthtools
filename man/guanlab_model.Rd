% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/models.R
\name{guanlab_model}
\alias{guanlab_model}
\title{This model was used to generate the top scoring
submission to the 2017 Parkinson's Disease Digital
Biomarker DREAM Challenge, Subchallenge 1
(https://www.synapse.org/#!Synapse:syn8717496/wiki/422884).}
\usage{
guanlab_model(sensor_data, models = load_guanlab_model)
}
\arguments{
\item{sensor_data}{An \code{n} x 4 data frame with columns \code{t}, \code{x},
\code{y}, \code{z} containing kinematic sensor (accelerometer or gyroscope)
measurements. Here \code{n} is the
total number of measurements, \code{t} is the timestamp of each measurement, and
\code{x}, \code{y} and \code{z} are linear axial measurements.}

\item{models}{A list of models to use for prediction.}
}
\value{
10 different "features", which are actually just 
predictions generated by the same neural net architecture
trained to different local minima.
}
\description{
It is recommended to first store the result of \code{load_guanlab_model}
to an R object, then pass that object to the \code{model} parameter.
Otherwise it is necessary to load the weights into the model each
time this function is called.
}
\details{
This model may be used to generate some robust predictions
to distinguish Parkinson's patients from controls.
}

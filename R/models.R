#' Neural net architecture for GuanLab's winning 2017 PDDB submission
#' 
#' This neural net architecture was used to generate the top 
#' scoring submission to the 2017 Parkinson's Disease Digital
#' Biomarker DREAM Challenge, Subchallenge 1
#' \url{https://www.synapse.org/#!Synapse:syn8717496/wiki/422884}.
#' 
#' It should be noted that GuanLab themselves wrote that:
#' "The parameters and structures of my network does not really matter,
#' as it is the simplest that can be seen in the deep learning field".
#' Nevertheless, this was the top scoring submission, and can be used
#' to generate some robust predictions to distinguish Parkinson's
#' patients from controls.
#' 
#' @return keras sequential model
guanlab_nn_architecture <- function() {
  # match default lasagne parameters of original model
  bn <- purrr::partial(keras::layer_batch_normalization,
                       epsilon = 1e-4, momentum = 0.9, center = T, scale = T)
  c1d <- purrr::partial(keras::layer_conv_1d,
                        strides = 1, padding = "valid",
                        kernel_initializer = "glorot_uniform",
                        bias_initializer = "zeros",
                        activation = "linear")
  mp <- purrr::partial(keras::layer_max_pooling_1d,
                       pool_size = 2L)
  relu <- purrr::partial(keras::layer_activation,
                         activation = "relu")
  model <- keras::keras_model_sequential() %>%
    c1d(filters = 8, kernel_size = 5, input_shape = c(4000, 3)) %>%
    bn() %>% relu() %>% mp() %>%
    c1d(filters = 16, kernel_size = 5) %>%
    bn() %>% relu() %>% mp() %>%
    c1d(filters = 32, kernel_size = 4) %>%
    bn() %>% relu() %>% mp() %>%
    c1d(filters = 32, kernel_size = 4) %>%
    bn() %>% relu() %>% mp() %>%
    c1d(filters = 64, kernel_size = 4) %>%
    bn() %>% relu() %>% mp() %>%
    c1d(filters = 64, kernel_size = 4) %>%
    bn() %>% relu() %>% mp() %>%
    c1d(filters = 128, kernel_size = 4) %>%
    bn() %>% relu() %>% mp() %>%
    c1d(filters = 128, kernel_size = 5) %>%
    bn() %>% relu() %>% mp() %>%
    keras::layer_flatten() %>%
    keras::layer_dense(units = 1,
                       activation = "sigmoid",
                       kernel_initializer = "glorot_uniform",
                       bias_initializer = "zeros")
  return(model)
}

#' Load the GuanLab model with weights.
#' 
#' @return list of keras sequential models
load_guanlab_model <- function() {
  weights <- guanlab_nn_weights
  models <- purrr::map(weights, function(w) {
    model <- guanlab_nn_architecture()
    model$set_weights(w)
    return(model)
  })
  return(models)
}

#' This model was used to generate the top scoring
#' submission to the 2017 Parkinson's Disease Digital
#' Biomarker DREAM Challenge, Subchallenge 1
#' (https://www.synapse.org/#!Synapse:syn8717496/wiki/422884).
#' 
#' It is recommended to first store the result of \code{load_guanlab_model}
#' to an R object, then pass that object to the \code{model} parameter.
#' Otherwise it is necessary to load the weights into the model each
#' time this function is called.
#' 
#' This model may be used to generate some robust predictions
#' to distinguish Parkinson's patients from controls.
#' 
#' @param sensor_data An \code{n} x 4 data frame with columns \code{t}, \code{x},
#' \code{y}, \code{z} containing kinematic sensor (accelerometer or gyroscope)
#' measurements. Here \code{n} is the
#' total number of measurements, \code{t} is the timestamp of each measurement, and
#' \code{x}, \code{y} and \code{z} are linear axial measurements.
#' @param models A list of models to use for prediction.
#' @return 10 different "features", which are actually just 
#' predictions generated by the same neural net architecture
#' trained to different local minima.
guanlab_model <- function(sensor_data, models = load_guanlab_model) {
  if (is.function(models)) { # load weights from file
    models <- models()
  }
  features <- purrr::map_dfc(models, function(model) {
    padding <- matrix(0, 4000 - dim(sensor_data)[1], 3)
    standard_sensor_data <- sensor_data %>%
      dplyr::select(-t) %>%
      purrr::map(~ (. - mean(.)) / sd(.)) %>%
      unlist() %>%
      matrix(ncol = 3, byrow = F)
    padded_sensor_data <- standard_sensor_data %>%
      rbind(padding) %>%
      keras::array_reshape(c(1, 4000, 3))
    proba <- model$predict_proba(padded_sensor_data)
    return(proba)
  })
  return(features)
}
% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/data_units_and_scaling.R
\name{set_units}
\alias{set_units}
\title{Set the units for meteorological point data.}
\usage{
set_units(point_data, units_name)
}
\arguments{
\item{point_data}{A harp_fcst object, or a data frame.}

\item{units_name}{The name of the units of the data, e.g. "m/s", "kg/m\^2" etc.}
}
\value{
A An object of the same type as \code{point_data}, but with the units
  column modified to contain \code{units_name}, or the units column added.
}
\description{
Note that the contents of the data are not changed in any way. Rather, if a
column called 'units' exists, its contents are modified to be that passed in
the units_name argument - if the 'units' column does not exist, it is added.
}

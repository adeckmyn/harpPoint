% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ens_rank_histogram.R
\name{ens_rank_histogram}
\alias{ens_rank_histogram}
\title{Rank histogram for an ensemble.}
\usage{
ens_rank_histogram(
  .fcst,
  parameter,
  groupings = "leadtime",
  jitter_fcst = NULL
)
}
\arguments{
\item{.fcst}{A \code{harp_fcst} object with tables that have a column for
observations, or a single forecast table.}

\item{parameter}{The name of the column for the observed data.}

\item{groupings}{The groups for which to compute the ensemble mean and
spread. See \link[dplyr]{group_by} for more information of how grouping
works.}

\item{jitter_fcst}{A function to perturb the forecast values by. This is used
to account for observation error in the rank histogram. For other
statistics it is likely to make little difference since it is expected that
the observations will have a mean error of zero.}
}
\value{
An object of the same format as the inputs but with data grouped for
  the \code{groupings} column(s) and columns for \code{rank} and
  \code{rank_count} that are nested together in a column with the name
  \code{rank_histogram}.
}
\description{
The rank histogram is computed as columns in a \code{harp_fcst} object.
Typically the scores are aggregated over lead time, but other grouping
variables can be chosen.
}

% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/LoadData.R
\name{add.in.indels}
\alias{add.in.indels}
\title{Add indels to an existing dataset}
\usage{
add.in.indels(dataset, indeldata, is.male, supported_chroms)
}
\arguments{
\item{dataset}{A data set object}

\item{indeldata}{A list of read in data.frames (one per sample) with output from dpclust3p}

\item{supported_chroms}{Chromosomes that are supported}
}
\value{
the provided dataset with indels added
}
\description{
Add indels to an existing dataset
}

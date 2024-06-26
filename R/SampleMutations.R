#
# Functions to downsample mutations
#

#' Sample a number of mutations from the dataset to reduce its size. The original
#' dataset object is kept within the returned dataset with label full.data
#' 
#' Note: Resampling an already sampled dataset will not work and returns the original
#' Note2: A conflict array will not be updated.
#' @param dataset The data set to use
#' @param num_muts_sample The number of mutations to sample
#' @param min_sampling_factor num_muts_sample*min_sampling_factor is the minimum number of mutations to have before sampling is applied. Use this multiplier to make sure we're not just sampling out a very low fraction of mutations (Default: 1.5)
#' @param sampling_method Integer selecting a sampling method. 1 is uniform sampling, 2 takes only subclonal mutations via a proportion test (Default: 1)
#' @param sample.snvs.only Boolean whether to only sample SNVs (supply TRUE) or to sample all mutation types (supply FALSE) (Default: TRUE)
#' @param remove.snvs Boolean whether to remove all SNVs (for clustering runs of only indels or CNAs) (Default: FALSE)
#' @return A dataset object with only the sampled mutations and a full.data field that contains the original dataset
sample_mutations = function(dataset, num_muts_sample, min_sampling_factor=1.5, sampling_method=1, sample.snvs.only=T, remove.snvs=F) {

  # Check if sampling already was done
  if (!is.na(dataset$sampling.selection)) {
    return(dataset)
  }
  
  # Get the data that is available for sampling
  avail_for_sampling = get_data_avail_for_sampling(dataset, sample.snvs.only, remove.snvs)
  
  # Check that the amount of data available for sampling is sufficient, if not, return the original dataset
  if (length(avail_for_sampling) < floor(min_sampling_factor*num_muts_sample)) {
    # print(paste("Num muts smaller than", min_sampling_factor, "*threshold, not performing sampling", sep=""))
    return(dataset)
  } else {
    print(paste("Sampling", num_muts_sample, "of", length(avail_for_sampling), "mutations", sep=" "))
  }
  
  # Store the original mutations
  full_data = list(chromosome=dataset$chromosome, position=dataset$position, WTCount=dataset$WTCount, mutCount=dataset$mutCount,
                   totalCopyNumber=dataset$totalCopyNumber, copyNumberAdjustment=dataset$copyNumberAdjustment,
                   non.deleted.muts=dataset$non.deleted.muts, kappa=dataset$kappa, mutation.copy.number=dataset$mutation.copy.number,
                   subclonal.fraction=dataset$subclonal.fraction, removed_indices=dataset$removed_indices,
                   chromosome.not.filtered=dataset$chromosome.not.filtered, mut.position.not.filtered=dataset$mut.position.not.filtered,
                   sampling.selection=NA, full.data=NA, most.similar.mut=NA, mutationType=dataset$mutationType, cellularity=dataset$cellularity,
                   conflict.array=dataset$conflict.array, phase=dataset$phase)
  
  
  if (sampling_method==1) {
    # Perform regular uniform sampling
    selection = do_uniform_sampling(avail_for_sampling, num_muts_sample)
    
  } else if (sampling_method==2) {
    # Take only subclonal mutations
    if (ncol(dataset$mutCount)==1) {
      print("Taking only subclonal data. This only works in single sample cases")
      selection = avail_for_sampling[which(dataset$subclonal.fraction[avail_for_sampling, 1] < 0.9)]
    } else {
      print("Taking only subclonal data does not work for multi-sample cases, returning all data available for sampling")
      selection = avail_for_sampling
    }
    
  } else {
    print("Unsupported sampling method supplied. No sampling performed.")
    return(dataset)
  }
  print(paste("Subsampled number of mutations: ", length(selection)))
  
  # Add CNA pseudo-SNVs if these were not to be sampled
  if (sample.snvs.only & !remove.snvs) {
    selection = c(selection, which(dataset$mutationType=="CNA"))
  }
  
  
  # Select all the data from the various matrices
  chromosome = as.matrix(dataset$chromosome[selection,])
  position = as.matrix(dataset$position[selection,])
  WTCount = as.matrix(dataset$WTCount[selection,])
  mutCount = as.matrix(dataset$mutCount[selection,])
  totalCopyNumber = as.matrix(dataset$totalCopyNumber[selection,])
  copyNumberAdjustment = as.matrix(dataset$copyNumberAdjustment[selection,])
  non.deleted.muts = dataset$non.deleted.muts[selection]
  kappa = as.matrix(dataset$kappa[selection,])
  mutation.copy.number = as.matrix(dataset$mutation.copy.number[selection,])
  subclonal.fraction = as.matrix(dataset$subclonal.fraction[selection,])
  mutationType = dataset$mutationType[selection]
  phase = dataset$phase[selection,]
  if (!is.na(dataset$conflict.array)) {
    conflict.array = dataset$conflict.array[selection, selection]
  } else {
    conflict.array = NA
  }

  # Don't update these - maybe this should be done, but not like this as the removed_indices matrix remains the same size as CNAs are added
  removed_indices = dataset$removed_indices
  most.similar.mut = get_most_similar_snv(full_data, selection)
  # # Map CNAs back onto themselves
  # most.similar.mut = c(most.similar.mut, which(full_data$mutationType=="CNA"))
  
  return(list(chromosome=chromosome, position=position, WTCount=WTCount, mutCount=mutCount, 
              totalCopyNumber=totalCopyNumber, copyNumberAdjustment=copyNumberAdjustment, 
              non.deleted.muts=non.deleted.muts, kappa=kappa, mutation.copy.number=mutation.copy.number, 
              subclonal.fraction=subclonal.fraction, removed_indices=dataset$removed_indices,
              chromosome.not.filtered=dataset$chromosome.not.filtered, mut.position.not.filtered=dataset$mut.position.not.filtered,
              sampling.selection=selection, full.data=full_data, most.similar.mut=most.similar.mut,
              mutationType=mutationType, cellularity=dataset$cellularity, conflict.array=conflict.array,
              phase=phase))
}

get_most_similar_snv = function(full_data, selection) {
  most.similar.mut = rep(1, length(full_data$chromosome))
  
  for (i in 1:length(full_data$chromosome)) { #[full_data$mutationType=="SNV"]
    if (i %in% selection) {
      # Save index of this mutation within selection - i.e. this row of the eventual mutation assignments must be selected
      most.similar.mut[i] = which(selection==i)
    } else {
      # Find mutation with closest CCF
      ccf.diff = matrix(full_data$subclonal.fraction[selection]-full_data$subclonal.fraction[i], ncol=1)
      curr = selection[which.min(abs(rowSums(ccf.diff)))]
      most.similar.mut[i] = which(selection==curr) # Saving index of most similar mut in the sampled data here for expansion at the end
    }
  }
  return(most.similar.mut)
}

#' Unsample a sampled dataset and expand clustering results with the mutations that were not used during clustering.
#' Mutations are assigned to the same cluster as the most similar mutation is assigned to
#' @param dataset A dataset object in which mutations have been sampled
#' @param clustering_result A clustering result object based on the downsampled mutations
#' @return A list containing the unsampled dataset and the clustering object with the unused mutations included
unsample_mutations = function(dataset, clustering_result) {
  # Update the cluster summary table with the new assignment counts
  best.node.assignments = clustering_result$best.node.assignments[dataset$most.similar.mut]
  cluster.locations = clustering_result$cluster.locations
  new_assignment_counts = table(best.node.assignments)
  for (cluster in names(new_assignment_counts)) {
    cluster.locations[cluster.locations[,1]==as.numeric(cluster), ncol(cluster.locations)] = new_assignment_counts[cluster]
  }
  
  # Not all assignment options return a full likelihood table
  if (any(!is.na(clustering_result$all.assignment.likelihoods))) {
    all.assignment.likelihoods = clustering_result$all.assignment.likelihoods[dataset$most.similar.mut,,drop=F]
  } else {
    all.assignment.likelihoods = NA
  }
  
  clustering = list(all.assignment.likelihoods=all.assignment.likelihoods,
                    best.node.assignments=best.node.assignments, 
                    best.assignment.likelihoods=clustering_result$best.assignment.likelihoods[dataset$most.similar.mut],
                    cluster.locations=cluster.locations)
  # Save the cndata, if available
  new_dataset = dataset$full.data
  new_dataset$cndata = dataset$cndata
  return(list(dataset=new_dataset, clustering=clustering))
}

#' Function that returns the indices of data that is available for sampling given
#' that one can choose to only sample SNVs, sample both SNVs and CNAs or remove SNVs
#' alltogether
#' @param dataset A dataset object
#' @param sample.snvs.only Boolean that if set to TRUE samples SNVs only. CNA indices should then lateron be added manually if they need to stay in the dataset
#' @param remove.snvs A boolean that if set to TRUE removes the SNVs from the dataset and returns just the CNA indices
#' @return A list of indices representing the data that can be sampled under the given restrictions
#' @author sd11
get_data_avail_for_sampling = function(dataset, sample.snvs.only, remove.snvs) {
  # Make inventory of what can be sampled
  if (sample.snvs.only & !remove.snvs) {
    # print("Sampling only SNVs")
    avail_for_sampling = which(dataset$mutationType=="SNV")
    
  } else if (remove.snvs) {
    # print("Sampling only CNAs, removing all SNVs")
    # Remove SNVs and sample CNAs
    avail_for_sampling = which(dataset$mutationType=="CNA")
    
  } else {
    # print("Sampling all data")
    avail_for_sampling = 1:nrow(dataset$chromosome)
  }
  return(avail_for_sampling)
}

#' Uniformly sample mutations
#' @param num_muts The total number of mutations in the dataset
#' @param num_muts_sample The number of mutations to sample
#' @return A vector with indices of mutations to select
#' @author sd11
do_uniform_sampling = function(avail_for_sampling, num_muts_sample) {
  selection = sample(avail_for_sampling)[1:num_muts_sample]
  selection = sort(selection)
  return(selection)
}

#' Control the spatial FDR
#'
#' Borrowing heavily from \code{cydar} which corrects for multiple-testing
#' using a weighting scheme based on the volumetric overlap over hyperspheres.
#' In the instance of graph neighbourhoods this weighting scheme can use graph
#' connectivity or incorpate different within-neighbourhood distances for the
#' weighted FDR calculation.
#' @param x.nhoods A list of vertices and the constituent vertices of their
#' neighbourhood
#' @param graph The kNN graph used to define the neighbourhoods
#' @param pvalues A vector of p-values calculated from a GLM or other appropriate
#' statistical test for differential neighbourhood abundance
#' @param weighting A string scalar defining which weighting scheme to use.
#' Choices are: vertex, edge, k-distance, neighbour-distance.
#' @param reduced.dimensions (optional) A \code{matrix} of cells X reduced dimensions used
#' to calculate the kNN graph. Only necessary if this function is being used
#' outside of \code{testNhoods} where the \code{\linkS4class{Milo}}
#' object is not available
#' @param distances (optional) A \code{matrix} of cell-to-cell distances or a list
#' of distance matrices, 1 per neighbourhood. Only necessary if this function is being
#' used outside of \code{testNhoods} where the \code{\linkS4class{Milo}}
#' object is not available.
#' @param indices (optional) A list of neighbourhood index vertices in the same order as the input neighbourhoods.
#' Only used for the k-distance weighting.
#'
#' @details Each neighbourhood is weighted according to the weighting scheme
#' defined. Vertex and edge use the respective graph connectivity measures
#' of the neighbourhoods, k-distance uses the distance to the kth nearest neighbour
#' of the index vertex, while neighbour-distance uses the average within-neighbourhood
#' Euclidean distance in reduced dimensional space. The frequency-weighted version of the
#' BH method is then applied to the p-values, as in \code{cydar}.
#'
#' @return A vector of adjusted p-values
#'
#' @author Adapted by Mike Morgan, original function by Aaron Lun
#'
#' @examples
#' NULL
#' @name graphSpatialFDR
NULL


#' @export
#' @importFrom igraph induced_subgraph vertex_connectivity edge_connectivity
#' @importFrom Matrix rowMeans
#' @importFrom stats dist
graphSpatialFDR <- function(x.nhoods, graph, pvalues, weighting='vertex', reduced.dimensions=NULL, distances=NULL, indices=NULL){

    # Discarding NA pvalues.
    haspval <- !is.na(pvalues)
    if (!all(haspval)) {
        coords <- coords[haspval, , drop=FALSE]
        pvalues <- pvalues[haspval]
    }

    if(weighting[1] == "none"){
        return(rep(NA_real_, length(pvalues)))
    }
    # if the weighting vector length > 1 then just take the first element as this is the default
    # is this a bit hacky?
    if(length(weighting) > 1){
        weighting <- weighting[1]
    }

    if(weighting %in% c("vertex", "edge")){
        # define the subgraph for each neighborhood then calculate the connectivity for each
        # this latter computation is quite slow - can it be sped up?
        # then loop over these sub-graphs to calculate the connectivity
        subgraphs <- lapply(1:length(x.nhoods[haspval]),
                            FUN=function(X) induced_subgraph(graph, x.nhoods[haspval][[X]]))
        if(weighting == "vertex"){
            t.connect <- lapply(subgraphs, FUN=function(EG) vertex_connectivity(EG))
        } else{
            t.connect <- lapply(subgraphs, FUN=function(EG) edge_connectivity(EG))
        }
    } else if(weighting == "neighbour-distance"){
        if(!is.null(reduced.dimensions)){
            t.connect <- lapply(1:length(x.nhoods[haspval]),
                                FUN=function(PG) {
                                    x.pcs <- reduced.dimensions[x.nhoods[haspval][[PG]], ]
                                    x.euclid <- as.matrix(dist(x.pcs))
                                    x.distdens <- mean(x.euclid[lower.tri(x.euclid, diag=FALSE)])
                                    return(x.distdens)})
        } else if(is.list(distances) & all(unlist(lapply(distances, class)) %in% c("matrix"))){
            t.connect <- unlist(lapply(distances, FUN=function(NHD) mean(rowMeans(NHD))))
        } else{
            stop("A matrix of reduced dimensions is required to calculate distances")
        }
    } else if(weighting == "k-distance"){
        # do we have a distance matrix for the vertex cell to it's kth NN?
        if(!is.null(distances) & !is.null(indices)){
            # use distances first as they are already computed
            # compute the distance to the kth nearest neighbour
            # this is just the most distant neighbour
            if(class(distances) %in% c("matrix")){
                t.connect <- unlist(lapply(indices, FUN=function(X) max(distances[X, ])))
            } else if(class(distances) %in% c("list")){
                t.connect <- unlist(lapply(indices, FUN=function(X) max(distances[[as.character(X)]])))
            } else{
                stop("Neighbourhood distances must be either a matrix or a list of matrices")
            }
        } else if(!is.null(reduced.dimensions) & !is.null(indices)){
            # find the kth NN and distance
            t.connect <- unlist(lapply(indices,
                                       FUN=function(X) max(findKNN(reduced.dimensions,
                                                                   get.distance=TRUE,
                                                                   subset=X, k=21)[["distance"]])))
        } else if(is.null(indices)){
            stop("No neighbourhood indices found - required to compute k-distance weighting")
        } else{
            stop("k-distance weighting requires either a distance matrix or reduced dimensions.")
        }
    } else{
        stop("Weighting option not recognised - must be either edge, vertex neighbour-distance or k-distance")
    }

    # use 1/connectivity as the weighting for the weighted BH adjustment from Cydar
    w <- 1/unlist(t.connect)
    w[is.infinite(w)] <- 0

    # Computing a density-weighted q-value.
    o <- order(pvalues)
    pvalues <- pvalues[o]
    w <- w[o]

    adjp <- numeric(length(o))
    adjp[o] <- rev(cummin(rev(sum(w)*pvalues/cumsum(w))))
    adjp <- pmin(adjp, 1)

    if (!all(haspval)) {
        refp <- rep(NA_real_, length(haspval))
        refp[haspval] <- adjp
        adjp <- refp
    }
    return(adjp)
}

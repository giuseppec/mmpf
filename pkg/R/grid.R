#' @title method to create a uniform grid on a variable
#'
#' @import checkmate
#'
#' @description generates an evenly spaced grid given an input vector, matrix, or \code{data.frame} which has size \code{length.out}.
#'
#' @param x a vector, matrix, or \code{data.frame} to create a grid on.
#' @param length.out an integer giving the length of the grid.
#'
#' @return an object of the same type as \code{x}, with \code{length.out} or fewer unique values.
#'
#' @note for unordered factors and characters, if \code{length.out < length(unique(x))} \code{length.out} is set to \code{length(unique(x))}. if \code{x} is a \code{data.frame} and this is true of some columns but not others, there will be a warning.
#' @examples
#'
#' data = data.frame(
#'   w = seq(0, 1, length.out = 5),
#'   x = factor(letters[1:5]),
#'   y = ordered(1:5),
#'   z = 1:5
#' )
#'
#' lapply(data, uniformGrid, length.out = 5)
#' @export
uniformGrid = function(x, length.out) {
  assertIntegerish(length.out, lower = 1L, any.missing = FALSE, len = 1L)
  UseMethod("uniformGrid")
}

#' @export
uniformGrid.numeric = function(x, length.out) {
  seq(min(x, na.rm = TRUE), max(x, na.rm = TRUE), length.out = length.out)
}

#' @export
uniformGrid.integer = function(x, length.out) {
  min.x = min(x, na.rm = TRUE)
  max.x = max(x, na.rm = TRUE)
  x.length = max.x - min.x
  if (length.out > x.length) {
    min.x:max.x
  } else {
    as.integer(round(seq.int(min.x, max.x, length.out = length.out)), 0)
  }
}

#' @export
uniformGrid.factor = function(x, length.out, ...) {
  x.length = length(unique(x))
  if (length.out >= x.length) {
    sort(unique(x))
  } else {
    if (is.ordered(x)) {
      unique(x)[uniformGrid(seq_len(x.length), length.out)]
    } else {
      warning("length.out is less than the number of levels")
      sort(sample(unique(x), size = length.out))
    }
  }
}

#' @export
uniformGrid.character = function(x, length.out, ...) {
  x.length = length(unique(x))
  if (length.out < x.length) {
    warning("length.out is less than the number of unique values")
  }
  sample(unique(x), size = min(length.out, x.length))
}

#' @export
uniformGrid.data.frame = function(x, length.out) {
  as.data.frame(lapply(x, uniformGrid, length.out = length.out),
    stringsAsFactors = FALSE)
}

#' @export
uniformGrid.matrix = function(x, length.out) {
  apply(x, 2, uniformGrid, length.out = length.out)
}

#' @title expands two data.frames using the Cartesian product
#' @description takes the cartesian product of two data.frames
#'
#' @import checkmate
#' @import data.table
#'
#' @param x a \code{data.frame}
#' @param y a \code{data.frame}
#' @return a \code{data.frame}
#'
#' @examples
#' x = data.frame("a" = 1:5, "b" = 6:10)
#' y = data.frame("z" = letters[1:5], "y" = letters[6:10])
#' cartesianExpand(x, y)
#' 
#' @export
cartesianExpand = function(x, y) {
  assertDataFrame(x, min.rows = 1L, min.cols = 1L, col.names = "named")
  assertDataFrame(y, min.rows = 1L, min.cols = 1L, col.names = "named")

  x$id = 1
  y$id = 1
  x = data.table(x, key = "id")
  y = data.table(y, key = "id")
  merge(x, y, all = TRUE, allow.cartesian = TRUE)[, !"id", with = FALSE]
}
#' @title make a uniform, random, or user-specified  grid over some columns of a data.frame, and combine it with a grid of points to integrate over.
#' @description makes a uniform, random, or user-specified grid over some columns of a data.frame and takes their Cartesian product with the other columns
#'
#' @import checkmate
#'
#' @param data a \code{data.frame} which must contain \code{vars} as well as at least one other column
#' @param vars character vector the columns in data to create the grid for
#' @param n two dimensional integer vector giving the resolution of the grid. the first element gives the grid on \code{vars} and the second on the other columns, which are sampled without replacement.
#' @param uniform logical, indicates whether a uniform grid is to be constructed.
#' @param points a named list which gives specific points for \code{vars}.
#' @param int.points a integer vector giving indices of the points in \code{data} to marginalize over.
#' @return a \code{data.frame} with at most \code{n} dimensions.
#'
#' @examples
#' data = data.frame(w = seq(0, 1, length.out = 5),
#'   x = factor(letters[1:5]),
#'   y = ordered(1:5),
#'   z = 1:5,
#'   r = letters[1:5],
#'   stringsAsFactors = FALSE)
#' makeDesign(data, "z", c(10, 5), TRUE)
#'
#' @export
makeDesign = function(data, vars, n, uniform = TRUE, points, int.points) {
  ## arg checks
  assertCharacter(vars, any.missing = FALSE, min.len = 1L, max.len = ncol(data), unique = TRUE)
  assertDataFrame(data, min.cols = length(vars),
    min.rows = if (!missing(int.points)) length(int.points) else n[2])
  assertSubset(vars, colnames(data), FALSE)
  assertFlag(uniform, FALSE)
  
  if (!missing(int.points)) {
    assertIntegerish(int.points, any.missing = FALSE, min.len = 1L)
  } else {
    assertInt(n[2], lower = 1)
  }
  
  if (!missing(points)) {
    assertList(points, types = sapply(data[, vars, drop = FALSE], function(x) class(x)[1]),
      any.missing = FALSE, len = length(vars))
    checkSetEqual(names(points), vars)
  } else {
    assertInt(n[1], lower = 1)
  }
  
  if (missing(points)) {
     ## create points for grid or sample from training data
    if (uniform) {
      if (length(vars) > 1) {
        ## combine individual grids
        points = expand.grid(sapply(vars,
          function(x) uniformGrid(data[[x]], length.out = n[1]), simplify = FALSE),
          stringsAsFactors = FALSE)
      } else {
        points = uniformGrid(data[[vars]], n[1])
        points = as.data.frame(points, stringsAsFactors = FALSE)
        colnames(points) = vars
      }
    } else {
      ## randomly sample points w/o replacement
      id = sample(1:nrow(data), n[1])
      points = data[id, vars, drop = FALSE]
    }
  } else {
    uniform = FALSE
    ## combine user specified points
    points = expand.grid(points, stringsAsFactors = FALSE)
  }

  if (missing(int.points)) {
    int.points = sample(seq_len(nrow(data)), min(n[2], nrow(data)))
  }

  ## combine points with sampled points
  if (!all(colnames(data) %in% vars))
    setDF(cartesianExpand(
      data[int.points, !colnames(data) %in% vars, drop = FALSE],
      points
    ))
  else
    points
}

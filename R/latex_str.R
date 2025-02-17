#' @export
#' @title add latex dependencies
#' @description Manually add flextable latex dependencies to
#' the knitr session via [knit_meta_add()].
#'
#' When enabling caching in 'R Markdown' documents for PDF output,
#' the flextable cached result is used directly. Call `add_latex_dep()` in a
#' non cached chunk so that flextable latex dependencies are added
#' to knitr metadata.
#' @param float load package 'float'
#' @param wrapfig load package 'wrapfig'
#' @return NULL
#' @examples
#' add_latex_dep()
#' @keywords internal
add_latex_dep <- function(float = FALSE, wrapfig = FALSE){

  pandoc_to <- opts_knit$get("rmarkdown.pandoc.to")
  if(is.null(pandoc_to)) pandoc_to <- ""
  if(!grepl("latex", pandoc_to)){
    return(invisible(NULL))
  }

  is_quarto <- isTRUE(knitr::opts_knit$get("quarto.version") > numeric_version("0"))

  fonts_ignore <- flextable_global$defaults$fonts_ignore
  fontspec_compat <- get_pdf_engine() %in% c("xelatex", "lualatex")
  if (!is_quarto && !fonts_ignore && !fontspec_compat) {
    warning("fonts used in `flextable` are ignored because ",
            "the `pdflatex` engine is used and not `xelatex` or ",
            "`lualatex`. You can avoid this warning by using the ",
            "`set_flextable_defaults(fonts_ignore=TRUE)` command or ",
            "use a compatible engine by defining `latex_engine: xelatex` ",
            "in the YAML header of the R Markdown document.",
            call. = FALSE
    )
  }
  if (fontspec_compat || is_quarto) {
    usepackage_latex("fontspec")
  }
  usepackage_latex("multirow")
  usepackage_latex("multicol")
  usepackage_latex("colortbl")
  usepackage_latex(
    name = "hhline",
    extra_lines= c("\\newlength\\Oldarrayrulewidth",
                   "\\newlength\\Oldtabcolsep")
  )

  latex_dependency(
    name = "hhline",
    extra_lines= c("\\newlength\\Oldarrayrulewidth",
                   "\\newlength\\Oldtabcolsep")
  )
  usepackage_latex("longtable")
  if(float) usepackage_latex("float")
  if(wrapfig) usepackage_latex("wrapfig")
  usepackage_latex("array")
  usepackage_latex("hyperref")
  invisible(NULL)
}


gen_raw_latex <- function(x, lat_container = latex_container_none(),
                          caption = "", topcaption = TRUE, quarto = FALSE) {
  dims <- dim(x)
  column_sizes <- dims$widths
  column_sizes_df <- data.frame(
    column_size = column_sizes,
    col_id = factor(x$col_keys, levels = x$col_keys),
    stringsAsFactors = FALSE
  )


  properties_df <- merge_table_properties(x)
  linespacing_df <- properties_df[, c("part", "ft_row_id", "col_id", "line_spacing")]
  dat <- runs_as_latex(
    x = x,
    chunk_data = fortify_run(x),
    ls_df = linespacing_df
  )

  # hhlines and vborders ----
  latex_borders_data_str <- latex_gridlines(properties_df)
  properties_df <- merge(properties_df, latex_borders_data_str$vlines, by = c("part", "col_id", "ft_row_id"))
  properties_df[, setdiff(grep("^border\\.", colnames(properties_df), value = TRUE), "border.width.left") := NULL]
  setorderv(properties_df, c("part", "col_id", "ft_row_id"))

  # cell background color -----
  properties_df[, c("background_color") := list(
    latex_cell_bgcolor(.SD$background.color)
  )]
  properties_df[, c("background.color") := NULL]

  # text direction ----
  properties_df[, c("text_direction_left", "text_direction_right") := list(
    latex_text_direction(.SD$text.direction, left = TRUE),
    latex_text_direction(.SD$text.direction, left = FALSE)
  )]
  properties_df[, c("text.direction") := NULL]

  # merge prop and text and sizes----
  cell_properties_df <- merge(properties_df, dat, by = c("part", "ft_row_id", "col_id"))
  cell_properties_df <- merge(cell_properties_df, column_sizes_df, by = c("col_id"))

  # update colspan -----
  cell_properties_df <- reverse_colspan(cell_properties_df)
  # add col sizes -----
  column_sizes_df <- calc_column_size(cell_properties_df, x$col_keys)
  cell_properties_df[, c("column_size") := NULL]
  cell_properties_df <- merge(cell_properties_df, column_sizes_df, by = c("part", "ft_row_id", "col_id"))

  # latex for multicolumn + add vert lines ----
  if ("fixed" %in% x$properties$layout) {
    augment_multicolumn_fixed(cell_properties_df)
  } else {
    augment_multicolumn_autofit(cell_properties_df)
  }

  # latex for multirow ----
  augment_multirow_fixed(cell_properties_df)

  # paste everything ----
  cell_properties_df[, c("txt") := list(
    paste0(
      .SD$multirow_left,
      .SD$text_direction_left,
      .SD$txt,
      .SD$text_direction_right,
      .SD$multirow_right
    )
  )]

  cell_properties_df[cell_properties_df$colspan < 1, c("txt") := list("")]

  cell_properties_df[, c("txt") := list(
    paste0(
      .SD$multicolumn_left,
      .SD$txt,
      .SD$multicolumn_right
    )
  )]
  cell_properties_df[
    cell_properties_df$rowspan < 1,
    c("txt") := list(
      NA_character_
    )
  ]
  setorderv(cell_properties_df, c("part", "ft_row_id", "col_id"))
  txt_data <- cell_properties_df[, list(txt = paste0(.SD$txt[!is.na(.SD$txt)], collapse = " & ")),
    by = c("part", "ft_row_id")
  ]

  # txt_data is now merged by row ----
  txt_data[, c("txt") := list(paste0(.SD$txt, " \\\\"))]
  setorderv(txt_data, c("part", "ft_row_id"))

  # add horiz lines ----
  txt_data <- merge(txt_data, latex_borders_data_str$hlines, by = c("part", "ft_row_id"), all.x = TRUE, all.y = TRUE)
  setorderv(txt_data, cols = c("part", "ft_row_id"))
  txt_data <- augment_part_separators(txt_data, inherits(lat_container, "latex_container_none") && !quarto)

  txt_data[, c("txt") := list(paste(
    .SD$hlines_t_strings,
    .SD$txt,
    .SD$hlines_b_strings,
    sep = "\n\n"
  ))]

  if (inherits(lat_container, "latex_container_none") && !quarto) {
    txt_data$part <- factor(as.character(txt_data$part),
      levels = c("header", "footer", "body")
    )
  } else {
    txt_data$part <- factor(as.character(txt_data$part),
      levels = c("header", "body", "footer")
    )
  }
  setorderv(txt_data, c("part", "ft_row_id"))

  # finalize ----
  if ("fixed" %in% x$properties$layout) {
    column_sizes_latex <- sprintf("|p{%.2fin}", column_sizes)
  } else {
    column_sizes_latex <- rep("c", length(dims$widths))
  }

  align_tag <- latex_table_align(x)

  table_start <- sprintf(
    "\\begin{longtable}[%s]{%s}",
    align_tag, paste(column_sizes_latex, collapse = "")
  )
  table_end <- "\\end{longtable}"
  latex <- paste0(txt_data$txt, txt_data$part_sep, collapse = "\n\n")

  if (inherits(lat_container, "latex_container_wrap")) {
    topcaption <- FALSE
  }

  latex <- paste(
    cline_cmd,
    table_start,
    if (topcaption) caption,
    latex,
    if (!topcaption) caption,
    table_end,
    sep = "\n\n"
  )

  latex
}

#' @importFrom data.table fcase
augment_multirow_fixed <- function(properties_df) {
  properties_df[, c("multirow_left", "multirow_right") :=
    list(
      fcase(
        .SD$colspan > 1,
        paste0(
          "\\multirow[",
          substr(.SD$vertical.align, 1, 1),
          "]{-",
          format_double(.SD$colspan, digits = 0),
          "}{*}{\\parbox{", format_double(.SD$width, digits = 2), "in}{"
        ),
        default = ""
      ),
      fcase(.SD$colspan > 1, "}}", default = "")
    )]
  properties_df
}

latex_colwidth <- function(x) {
  grid_dat <- x[, .SD, .SDcols = c("part", "ft_row_id", "col_id", "rowspan", "border.width.left", "column_size")]
  grid_dat[, c('hspan_id') := list(calc_grid_span_group(.SD$rowspan)), by = c("part", "ft_row_id")]

  # bdr sum of width
  bdr_dat <- grid_dat[, list(col_id = first(.SD$col_id), border_widths = sum(.SD$border.width.left[-1])), by = c("part", "ft_row_id", "hspan_id")]
  bdr_dat$hspan_id <- NULL
  bdr_dat <- bdr_dat[bdr_dat$border_widths > 0,]

  grid_dat <- merge(grid_dat, bdr_dat, by = c("part", "ft_row_id", "col_id"), all.x = TRUE)

  colwidths <- paste0(
    "\\dimexpr ", format_double(grid_dat$column_size, 2), "in+",
    format_double((grid_dat$rowspan - 1) * 2, digits = 0),
    "\\tabcolsep"
  )

  # if necessary, add bdr width
  bdr_width_instr <- character(length(colwidths))
  bdr_width_instr[!is.na(grid_dat$border_widths)] <-
    paste0(
      "+",
      format_double(grid_dat$border_widths[!is.na(grid_dat$border_widths)], digits = 2),
      "pt")

  paste0(colwidths, bdr_width_instr)
}


augment_multicolumn_autofit <- function(properties_df) {
  stopifnot(is.data.table(properties_df))

  properties_df[, c("multicolumn_left", "multicolumn_right") :=
    list(
      paste0(
        "\\multicolumn{",
        format_double(.SD$rowspan, digits = 0),
        "}{",
        .SD$vborder_left,
        ">{", .SD$background_color, "}",
        substr(.SD$text.align, 1, 1),
        .SD$vborder_right,
        "}{"
      ),
      "}"
    )]
  properties_df
}
augment_multicolumn_fixed <- function(properties_df) {
  stopifnot(is.data.table(properties_df))

  properties_df[, c("multicolumn_left", "multicolumn_right") :=
    list(
      paste0(
        "\\multicolumn{", format_double(.SD$rowspan, digits = 0), "}{",
        .SD$vborder_left,
        ">{", .SD$background_color,
        c("center" = "\\centering", left = "\\raggedright", right = "\\raggedleft")[.SD$text.align],
        "}",
        "p{", latex_colwidth(.SD), "}",
        .SD$vborder_right,
        "}{"
      ),
      "}"
    )]
  properties_df
}

augment_part_separators <- function(z, no_container = TRUE) {

  part_separators <- merge(z[, c("part", "ft_row_id")],
    merge(z[, list(ft_row_id = max(.SD$ft_row_id)), by = "part"],
      data.frame(
        part = factor(c("header", "body", "footer"), levels = c("header", "body", "footer")),
        part_sep = if(no_container) c("\\endhead", "", "\\endfoot") else c("\\endhead", "", ""),
        stringsAsFactors = FALSE
      ),
      by = c("part")
    ),
    by = c("part", "ft_row_id"), all.x = TRUE, all.y = FALSE
  )
  part_separators$part_sep[is.na(part_separators$part_sep)] <- ""
  setorderv(part_separators, c("part", "ft_row_id"))

  z <- merge(z, part_separators, by = c("part", "ft_row_id"))
  z
}


# col/row spans -----
fill_NA <- function(x) {
  which.na <- c(which(!is.na(x)), length(x) + 1)
  values <- na.omit(x)

  if (which.na[1] != 1) {
    which.na <- c(1, which.na)
    values <- c(values[1], values)
  }
  diffs <- diff(which.na)
  return(rep(values, times = diffs))
}


reverse_colspan <- function(df) {
  setorderv(df, cols = c("part", "col_id", "ft_row_id"))
  df[, c("col_uid") := list(UUIDgenerate(n = nrow(.SD))), by = c("part", "ft_row_id")]
  df[df$colspan < 1, c("col_uid") := list(NA_character_)]
  df[, c("col_uid") := list(fill_NA(.SD$col_uid)), by = c("part", "col_id")]

  df[, c("ft_row_id",
         "vborder_left", "vborder_right") :=
    list(
      rev(.SD$ft_row_id),
      rev(.SD$vborder_left),
      rev(.SD$vborder_right)
    ), by = c("col_uid")]
  df[, c("col_uid") := NULL]
  setorderv(df, cols = c("part", "ft_row_id", "col_id"))
  df
}

calc_column_size <- function(df, levels) {
  z <- df[, c("col_id", "part", "ft_row_id", "rowspan", "column_size")]
  z$col_id <- factor(z$col_id, levels = levels)
  setorderv(z, cols = c("part", "ft_row_id", "col_id"))
  z[, c("col_uid") := list(UUIDgenerate(n = nrow(.SD))), by = c("part", "ft_row_id")]
  z[z$rowspan < 1, c("col_uid") := list(NA_character_)]
  z[, c("col_uid") := list(fill_NA(.SD$col_uid)), by = c("part", "ft_row_id")]
  z[, c("column_size") := list(sum(.SD$column_size, na.rm = TRUE)), by = c("part", "ft_row_id", "col_uid")]
  z[, c("col_uid", "rowspan") := NULL]
  setorderv(z, cols = c("part", "ft_row_id", "col_id"))
  setDT(z)
  z
}

# tools ----
#' @importFrom knitr knit_meta_add
#' @importFrom rmarkdown latex_dependency
usepackage_latex <- function(name, ...) {
  knit_meta_add(list(latex_dependency(name, ...)))
}

merge_table_properties <- function(x) {
  cell_data <- fortify_style(x, "cells")
  par_data <- fortify_style(x, "pars")
  setDT(cell_data)
  setDT(par_data)

  cell_data[, c("width", "height", "hrule") := NULL]
  cell_data <- merge(cell_data, fortify_width(x), by = "col_id")
  cell_data <- merge(cell_data, fortify_height(x), by = c("part", "ft_row_id"))
  cell_data <- merge(cell_data, fortify_span(x), by = c("part", "ft_row_id", "col_id"))

  oldnames <- grep("^border\\.", colnames(cell_data), value = TRUE)
  newnames <- paste0("paragraph.", oldnames)
  setnames(par_data, old = oldnames, new = newnames)
  cell_data <- merge(cell_data, par_data, by = c("part", "ft_row_id", "col_id"))
  cell_data$col_id <- factor(cell_data$col_id, levels = x$col_keys)
  setorderv(cell_data, c("part", "ft_row_id", "col_id"))
  cell_data
}

#' @importFrom utils compareVersion packageVersion
get_pdf_engine <- function() {

  if (compareVersion(as.character(packageVersion("rmarkdown")), "1.10.14") < 0) {
    stop("package rmarkdown >= 1.10.14 is required to use this function")
  }

  pandoc_args <- knitr::opts_knit$get("rmarkdown.pandoc.args")
  rd <- grep("--pdf-engine", pandoc_args)
  if (length(rd)) {
    engine <- pandoc_args[rd + 1]
  } else {
    engine <- "pdflatex"
  }
  engine
}


latex_table_align <- function(x) {
  ft.align <- x$properties$align
  if ("left" %in% ft.align) {
    align_tag <- "l"
  } else if ("right" %in% ft.align) {
    align_tag <- "r"
  } else {
    align_tag <- "c"
  }
  align_tag
}

# latex_container -----
latex_container_none <- function(){
  x <- list()
  class(x) <- c("latex_container_none", "latex_container")
  x
}
latex_container_float <- function(){
  x <- list()
  class(x) <- c("latex_container_float", "latex_container")
  x
}
latex_container_wrap <- function(placement = "l"){
  stopifnot(
    length(placement) == 1,
    placement %in% c("l", "r", "i", "o")
  )
  x <- list(placement = placement)
  class(x) <- c("latex_container_wrap", "latex_container")
  x
}
latex_container_str <- function(x, latex_container, quarto = FALSE, ...){
  UseMethod("latex_container_str", latex_container)
}
latex_container_str.latex_container_none <- function(x, latex_container, quarto = FALSE, ...) {
  c("", "")
}

latex_container_str.latex_container_float <- function(x, latex_container, quarto = FALSE, ...) {
  c("\\begin{table}", "\\end{table}")
}
latex_container_str.latex_container_wrap <- function(x, latex_container, quarto = FALSE, ...) {

  str <- paste0("\\begin{wraptable}{", latex_container$placement, "}")

  if (x$properties$layout %in% "fixed") {
    w <- sprintf("%.02fin", flextable_dim(x)$widths)
  } else {
    w <- "0pt"
  }
  c(
    paste0(str, "{", w, "}"),
    "\\end{wraptable}"
  )
}

convert_doc_to_pdf <- function(doc_path) {
  if (!file.exists(doc_path)) stop("File does not exist: ", doc_path)
  if (!grepl("\\.doc$", doc_path, ignore.case = TRUE)) stop("Input file must be a .doc file")
  
  soffice_path <- "/Applications/LibreOffice.app/Contents/MacOS/soffice"
  if (!file.exists(soffice_path)) stop("LibreOffice not found at expected path. Is it installed?")
  
  out_dir <- dirname(doc_path)
  
  cmd <- c(
    "--headless",
    "--convert-to", "pdf",
    "--outdir", shQuote(out_dir),
    shQuote(doc_path)
  )
  
  result <- system2(soffice_path, args = cmd, wait = TRUE)
  
  pdf_path <- sub("\\.doc$", ".pdf", doc_path, ignore.case = TRUE)
  
  # Wait briefly to ensure output file is written
  for (i in 1:10) {
    if (file.exists(pdf_path)) break
    Sys.sleep(0.5)
  }
  
  if (!file.exists(pdf_path)) stop("PDF not created. Conversion may have failed.")
  message("PDF saved to: ", pdf_path)
  return(invisible(pdf_path))
}


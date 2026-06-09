;;; ─────────────────────────────────────────────────────────────
;;;                 NASSLISP MASSPURGE V5
;;; ─────────────────────────────────────────────────────────────
;;; note the dcl and lsp files need to be in the same folder

(vl-load-com)

;;; ── Helper: split string ─────────────────────────────────────
(defun str_split (str delim / result token i ch)
  (setq result '() token "" i 0)
  (while (<= (setq i (1+ i)) (strlen str))
    (setq ch (substr str i 1))
    (if (= ch delim)
      (progn
        (if (> (strlen token) 0)
          (setq result (append result (list token))))
        (setq token ""))
      (setq token (strcat token ch))))
  (if (> (strlen token) 0)
    (setq result (append result (list token))))
  result
)

;;; ── Windows folder browser ───────────────────────────────────
(defun browse_for_folder ( / shell folder picked path hwnd)
  (setq hwnd  (vla-get-hwnd (vlax-get-acad-object)))
  (setq shell (vlax-create-object "Shell.Application"))
  (setq folder
    (vlax-invoke shell 'BrowseForFolder
      hwnd
      "Select folder containing DWG files:"
      (+ 64 128)
      0
    )
  )
  (setq path nil)
  (if folder
    (progn
      (setq picked (vlax-get folder 'Self))
      (setq path   (vlax-get picked 'Path))
      (vlax-release-object picked)
      (vlax-release-object folder)
    )
  )
  (vlax-release-object shell)
  path
)

;;; ── Write DCL to TEMP ────────────────────────────────────────
(defun write_dcl ( / f path)
  (setq path (strcat (getvar "TEMPPREFIX") "batch_purge.dcl"))
  (setq f (open path "w"))
  (write-line "batch_purge : dialog {"                                         f)
  (write-line "  label = \"Batch Purge Drawings - Plant 3D 2025\";"                  f)
  (write-line "  : text { key = \"lbl_folder\"; label = \"No folder selected.\"; width = 58; }" f)
  (write-line "  : list_box {"                                                       f)
  (write-line "    key      = \"dwg_list\";"                                         f)
  (write-line "    label    = \"Select drawings (Ctrl+click for multiple):\";"       f)
  (write-line "    multiple_select = true;"                                          f)
  (write-line "    height   = 12;"                                                   f)
  (write-line "    width    = 60;"                                                   f)
  (write-line "  }"                                                                  f)
  (write-line "  : row {"                                                            f)
  (write-line "    : button { key = \"btn_browse\";  label = \"Browse Folder...\"; width = 20; }" f)
  (write-line "    : button { key = \"btn_selall\";  label = \"Select All\";        width = 14; }" f)
  (write-line "    : button { key = \"btn_selnone\"; label = \"Clear All\";          width = 12; }" f)
  (write-line "  }"                                                                  f)
  (write-line "  : toggle { key = \"tog_nested\"; label = \"Purge nested items (recommended)\"; value = \"1\"; }" f)
  (write-line "  : toggle { key = \"tog_audit\";  label = \"Run AUDIT before purge\";           value = \"1\"; }" f)
  (write-line "  : toggle { key = \"tog_backup\"; label = \"Delete .bak files after save\";     value = \"1\"; }" f)
  (write-line "  spacer;"                                                            f)
  (write-line "  ok_cancel;"                                                         f)
  (write-line "}"                                                                    f)
  (close f)
  path
)

;;; ── Main command ─────────────────────────────────────────────
(defun C:MP ( / dcl_path dcl_id file_list pick_dir raw_files dir_clean
                        sel_idx do_nested do_audit do_bak result
                        idx_list tok idx dwg
                        acad docs doc_obj saved_size new_size bak_file
                        pass_count done total_purged all_idx n)

  (setq dcl_path (write_dcl))
  (if (not (findfile dcl_path))
    (progn (alert "ERROR: Could not write DCL to TEMP.") (exit))
  )

  (setq dcl_id (load_dialog dcl_path))
  (if (or (not dcl_id) (minusp dcl_id))
    (progn (alert "ERROR: load_dialog failed.") (exit))
  )
  (if (not (new_dialog "batch_purge" dcl_id))
    (progn (unload_dialog dcl_id) (alert "ERROR: new_dialog failed.") (exit))
  )

  (setq file_list '())

  ;; ── Browse ────────────────────────────────────────────────────
  (action_tile "btn_browse"
    "(setq pick_dir (browse_for_folder))
     (if pick_dir
       (progn
         (setq raw_files (vl-directory-files pick_dir \"*.dwg\" 1))
         (if raw_files
           (progn
             (setq dir_clean (vl-string-right-trim \"\\\\/\" pick_dir))
             (setq file_list
               (mapcar
                 (function (lambda (f) (strcat dir_clean \"\\\\\" f)))
                 raw_files))
             (set_tile \"lbl_folder\" (strcat \"Folder: \" dir_clean))
             (start_list \"dwg_list\" 3)
             (mapcar
               (function (lambda (f) (add_list (vl-filename-base f))))
               file_list)
             (end_list)
             (set_tile \"dwg_list\" \"0\")
           )
           (alert \"No .dwg files found in that folder.\")
         )
       )
     )"
  )

  ;; ── Select all ───────────────────────────────────────────────
  (action_tile "btn_selall"
    "(if file_list
       (progn
         (setq all_idx \"\" n 0)
         (repeat (length file_list)
           (setq all_idx (strcat all_idx (if (= n 0) \"\" \" \") (itoa n)))
           (setq n (1+ n)))
         (set_tile \"dwg_list\" all_idx)
       )
     )"
  )

  ;; ── Clear ────────────────────────────────────────────────────
  (action_tile "btn_selnone"
    "(set_tile \"dwg_list\" \"\")"
  )

  ;; ── OK ───────────────────────────────────────────────────────
  (action_tile "accept"
    "(setq sel_idx   (get_tile \"dwg_list\")
           do_nested (get_tile \"tog_nested\")
           do_audit  (get_tile \"tog_audit\")
           do_bak    (get_tile \"tog_backup\"))
     (if (or (not sel_idx) (= sel_idx \"\"))
       (alert \"Please select at least one drawing.\")
       (done_dialog 1)
     )"
  )

  (action_tile "cancel" "(done_dialog 0)")

  (setq result (start_dialog))
  (unload_dialog dcl_id)

  ;; ── Process ───────────────────────────────────────────────────
  (if (and (= result 1) sel_idx (/= sel_idx ""))
    (progn
      ;; Build index list
      (setq idx_list '())
      (foreach tok (str_split sel_idx " ")
        (if (> (strlen tok) 0)
          (setq idx_list (append idx_list (list (atoi tok))))))

      (setq acad (vlax-get-acad-object))
      (setq docs (vla-get-documents acad))
      (setq total_purged 0)

      (foreach idx idx_list
        (setq dwg (nth idx file_list))
        (if (and dwg (findfile dwg))
          (progn
            (princ (strcat "\n\n--- Processing: " (vl-filename-base dwg) " ---"))

            ;; Get file size before
            (setq saved_size (vl-file-size dwg))
            (princ (strcat "\n    Size before: " (rtos (/ saved_size 1024.0) 2 1) " KB"))

            ;; ── Open via ActiveX natively ──
            (setq doc_obj (vla-open docs dwg :vlax-false))

            ;; ── Audit ────────────────────────────────────────────
            (if (= do_audit "1")
              (progn
                (princ "\n    Running AUDIT...")
                ;; Fixes errors without switching document control
                (vla-auditinfo doc_obj :vlax-true) 
              )
            )

            ;; ── Purge natively ───────────────────────────────────
            (princ "\n    Purging...")
            
            ;; 4 passes to handle deep nesting issues safely via pure ActiveX
            (repeat (if (= do_nested "1") 4 1)
              (vla-PurgeAll doc_obj)
            )

            ;; ── Save & Close Synchronously ───────────────────────
            (princ "\n    Saving and closing...")
            (vla-save doc_obj)
            (vla-close doc_obj :vlax-false)
            
            ;; Release the object explicitly from memory
            (vlax-release-object doc_obj)

            ;; ── Report size reduction ─────────────────────────────
            (setq new_size (vl-file-size dwg))
            (princ (strcat "\n    Size after:  " (rtos (/ new_size 1024.0) 2 1) " KB"))
            (if (> saved_size 0)
              (princ (strcat "\n    Saved:       "
                (rtos (/ (- saved_size new_size) 1024.0) 2 1) " KB ("
                (rtos (* (/ (float (- saved_size new_size)) saved_size) 100) 2 1) "%)"))
            )

            ;; ── Delete .bak ──────────────────────────────────────
            (if (= do_bak "1")
              (progn
                (setq bak_file
                  (strcat (vl-filename-directory dwg) "\\"
                          (vl-filename-base dwg) ".bak"))
                (if (findfile bak_file)
                  (progn
                    (vl-file-delete bak_file)
                    (princ "\n    .bak deleted"))
                )
              )
            )

            (setq total_purged (1+ total_purged))
            (princ (strcat "\n    -> DONE: " (vl-filename-base dwg)))
          )
          ;; File not found
          (princ (strcat "\n    -> SKIPPED (not found): " (if dwg dwg "nil")))
        )
      )

      (alert
        (strcat "Batch purge complete!\n"
                (itoa total_purged) " drawing(s) processed.\n"
                "Check the command line for size reduction details."))
    )
    (princ "\nBatchPurge cancelled.")
  )
  (princ)
)

(princ "\nThank you for choosing NASSLISP. MASSPURGE loaded. Type MP to run.")
(princ)

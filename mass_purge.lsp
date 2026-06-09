;;; ─────────────────────────────────────────────
;;;  BATCHPURGE - Batch Purge for Plant 3D 2025
;;; ─────────────────────────────────────────────

(vl-load-com)

;;; ── Helper: split string by delimiter ────────
(defun str_split (str delim / result token i ch)
  (setq result '()  token ""  i 0)
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

;;; ── Windows BrowseForFolder dialog via ActiveX ──
(defun browse_for_folder ( / shell folder picked path)
  (setq shell  (vlax-create-object "Shell.Application"))
  (setq folder (vlax-invoke shell 'BrowseForFolder 0 "Select folder with DWG files" 0 0))
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

;;; ── Write DCL to TEMP ────────────────────────
(defun write_dcl ( / f path)
  (setq path (strcat (getvar "TEMPPREFIX") "batch_purge.dcl"))
  (setq f (open path "w"))
  (write-line "batch_purge : dialog {"                                          f)
  (write-line "  label = \"Batch Purge Drawings\";"                             f)
  (write-line "  : text { label = \"Folder:\"; key = \"lbl_folder\"; width = 55; }" f)
  (write-line "  : list_box {"                                                  f)
  (write-line "    key = \"dwg_list\";"                                         f)
  (write-line "    label = \"Select drawings (Ctrl+click for multiple):\";"     f)
  (write-line "    multiple_select = true;"                                     f)
  (write-line "    height = 12;"                                                f)
  (write-line "    width = 60;"                                                 f)
  (write-line "  }"                                                             f)
  (write-line "  : row {"                                                       f)
  (write-line "    : button { key = \"btn_browse\";  label = \"Browse Folder...\"; width = 20; }" f)
  (write-line "    : button { key = \"btn_selall\";  label = \"Select All\";       width = 14; }" f)
  (write-line "    : button { key = \"btn_selnone\"; label = \"Clear All\";        width = 12; }" f)
  (write-line "  }"                                                             f)
  (write-line "  : toggle { key = \"tog_backup\"; label = \"Delete .bak files after purge\"; value = \"1\"; }" f)
  (write-line "  : toggle { key = \"tog_audit\";  label = \"Run AUDIT before purge\";        value = \"0\"; }" f)
  (write-line "  spacer;"                                                       f)
  (write-line "  ok_cancel;"                                                    f)
  (write-line "}"                                                               f)
  (close f)
  path
)

;;; ── Main command ─────────────────────────────
(defun C:BATCHPURGE ( / dcl_path dcl_id file_list pick_dir
                        sel_idx do_bak do_audit result
                        idx_list idx dwg)

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

  ;; ── Browse: real Windows folder picker ───────
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

  ;; ── Select all ───────────────────────────────
  (action_tile "btn_selall"
    "(if file_list
       (progn
         (setq all_idx \"\"  n 0)
         (repeat (length file_list)
           (setq all_idx (strcat all_idx (if (= n 0) \"\" \" \") (itoa n)))
           (setq n (1+ n)))
         (set_tile \"dwg_list\" all_idx)
       )
     )"
  )

  ;; ── Clear all ────────────────────────────────
  (action_tile "btn_selnone"
    "(set_tile \"dwg_list\" \"\")"
  )

  ;; ── OK ───────────────────────────────────────
  (action_tile "accept"
    "(setq sel_idx  (get_tile \"dwg_list\")
           do_bak   (get_tile \"tog_backup\")
           do_audit (get_tile \"tog_audit\"))
     (if (or (not sel_idx) (= sel_idx \"\"))
       (alert \"Please select at least one drawing.\")
       (done_dialog 1)
     )"
  )

  (action_tile "cancel"
    "(done_dialog 0)"
  )

  (setq result (start_dialog))
  (unload_dialog dcl_id)

  ;; ── Process files ─────────────────────────────
  (if (and (= result 1) sel_idx (/= sel_idx ""))
    (progn
      (setq idx_list '())
      (foreach tok (str_split sel_idx " ")
        (if (> (strlen tok) 0)
          (setq idx_list (append idx_list (list (atoi tok))))))

      (foreach idx idx_list
        (setq dwg (nth idx file_list))
        (if (and dwg (findfile dwg))
          (progn
            (princ (strcat "\nOpening: " (vl-filename-base dwg)))
            (command "_.OPEN" dwg)
            (command "")
            (if (= do_audit "1")
              (command "_.AUDIT" "_Y"))
            (repeat 3
              (command "_.PURGE" "_All" "*" "_No"))
            (command "_.QSAVE")
            (if (= do_bak "1")
              (progn
                (setq bak_file
                  (strcat (vl-filename-directory dwg)
                          (vl-filename-base dwg) ".bak"))
                (if (findfile bak_file)
                  (vl-file-delete bak_file))))
            (command "_.CLOSE")
            (princ (strcat "  -> Done: " (vl-filename-base dwg)))
          )
          (princ (strcat "\n  -> SKIPPED (not found): " (itoa idx)))
        )
      )
      (alert "Batch purge complete!")
    )
    (princ "\nBatchPurge cancelled.")
  )
  (princ)
)

(princ "\nBATCHPURGE loaded. Type BATCHPURGE to run.")
(princ)

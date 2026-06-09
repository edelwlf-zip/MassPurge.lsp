batch_purge : dialog {
  label = "Batch Purge Drawings";
  : list_box {
    key = "dwg_list";
    label = "Select drawings to purge:";
    multiple_select = true;
    height = 12;
    width = 60;
  }
  : row {
    : button { key = "btn_browse"; label = "Browse Folder..."; width = 18; }
    : button { key = "btn_selall"; label = "Select All"; width = 14; }
    : button { key = "btn_selnone"; label = "Clear"; width = 10; }
  }
  : toggle { key = "tog_backup"; label = "Delete .bak files after purge"; value = "1"; }
  : toggle { key = "tog_audit";  label = "Run AUDIT before purge"; value = "0"; }
  spacer;
  ok_cancel;
}

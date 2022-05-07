open Printf

let bool_print_debug = ref false

let print_debug str =
  if !bool_print_debug then fprintf stdout str
  else ifprintf stdout str

exception No_repo
exception Not_exists

module IdMap = Map.Make(String)

let mkdir_num = 0o775
let mkfile_num = 0o664

let real_cwd = ref "" 

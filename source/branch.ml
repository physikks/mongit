open Printf
open Root

(* ===== LIST ===== *)
let cmd_list () =
  Outils.init () ;
  printf "List of branches : " ;
  List.iter 
    (fun br -> if br <> !branch then printf "%s " br 
    else (printf "\x1B[34m%s\x1B[97m " br)) (Outils.list_br ()) ;
  print_newline ()
(* ================= *)


(* ===== CREATE ===== *)
let copy_tree br1 br2 =
  let op = Outils.sha_name (Outils.with_branch br1 "")
  and np = Outils.sha_name (Outils.with_branch br2 "") in
  let rec aux op np dir =
    let op = Filename.concat !dr_trees op
    and np = Filename.concat !dr_trees np in
    let ic = Scanf.Scanning.open_in op
    and oc = open_out np in
    try while true do
      Scanf.bscanf ic "%s %s %s\n" 
      (fun t bn k -> fprintf oc "%s %s %s\n" t bn
      (if t="file" then k else (
       let subdir = Filename.concat dir bn in
       let np = (Outils.sha_name (Outils.with_branch br2 subdir)) in
       aux k np subdir; np)))
    done with | End_of_file -> Scanf.Scanning.close_in ic ; close_out oc
  in
  aux op np ""

let duplicate_keys br1 br2 = (*-> files/all_fkeys*)
  let tbl_fkeys = Outils.load_tbl_fkeys () in
  let rec fct = function
    | [] -> []
    | h::q when h=br1 -> br2 :: h :: (fct q)
    | h::q -> h :: (fct q)
  in
  let new_tbl = IdMap.map fct tbl_fkeys in
  Outils.print_tbl_fkeys new_tbl


let create br1 new_br =
  if List.mem new_br (Outils.list_br ()) then 
  ( eprintf "There already exists a branch called %s.\n" new_br ; exit 1) ;
  copy_tree br1 new_br ;
  duplicate_keys br1 new_br ;
  Outils.set_commit new_br (Outils.find_commit br1)


let cmd_create new_br =
  Outils.init () ;
  if new_br = "tmp_for_merge" then
    ( eprintf "Sorry \"tmp_for_merge\" is a special branch name.\n" ; exit 1) ;
  create !branch new_br ;
  printf 
    "%s has been successfully created.\n\
    \"mg -branch -switch %s\" might be a good idea.\n"
    new_br new_br
(* ================= *)


(* ===== DELETE ===== *)
(* Commande uniquement utilisé en interne pour supprimer des branches tmp.
   Pourrait causer de très gros dégats. *)
let delete br =
  Outils.remove (Filename.concat !dr_brnch br) ;
  Tree.erase (Outils.sha_name (Outils.with_branch br "")) ;
      (Outils.load_tbl_fkeys ())
  |>  (IdMap.map (Outils.list_rm br))
  |>  (Outils.flush_tbl_fkeys)
(* ================= *)


(* ===== SWITCH ===== *)
let cmd_switch br =
  Outils.init () ;
  if not (List.mem br (Outils.list_br ())) then
  (eprintf "There is no branch called %s.\n" br ; exit 1) ;
  let ic = open_in !to_be in
  begin try ignore (input_line ic) ; (* devrait raise EOF *)
    eprintf "The \"to_be_commited\" file have been erased \
             to avoid problems with the branch switch.\n" ;
    close_in ic ;
    Outils.empty_file !to_be
  with | End_of_file -> () end ;
  Outils.branch_switch br ;
  printf "The current branch has switched from %s to %s.\n"
    (Outils.branch_former ()) br
(* ================= *)


(* ===== GRAPH ===== *)
(* On construit 2 graphes, gup (goes_up) qui à un commit associe 
   ses parents et gdown (goes_down) qui donne ses enfants. *)
(* En soit les commits sont des arêtes d'un état vers un autre.
   Mais usuellement on les confond avec les noeuds d'un arbre. 
   Ce qui ne pose pas de problème jusqu'aux merges, où un 
   commit peut avoir plusieurs parents. Ce qui n'a aucun sens pour
   une arête dans un arbre. Pour résoudre le problème je crée un
   un commit "merge" tampon.
   On utilise une table tbl_to_merge pour signaler les commits
   qui sont des résultantes d'un merge. 
*)
let make_commit_graph commits =
  List.fold_left 
  (fun (gup,gdown,tbl_to_merge) cm -> 
    let tmp_commit = Filename.concat !dr_comms "tmp_commit" in
    Outils.load_fn cm !dr_comms tmp_commit ;
    let ic = Scanf.Scanning.open_in tmp_commit in
    let list_pcm , tbl_to_merge =
    Scanf.bscanf ic "%s\n" ( function 
      | "SIMPLE" -> 
        Scanf.bscanf ic "Parent commit : %s\n" (fun pcm -> [pcm]) ,
        tbl_to_merge
      | _(*MERGE*)  ->  
        Scanf.bscanf ic "Resulting commits : %s and %s\n"
        (fun rcm1 rcm2 -> [rcm1;rcm2] ,
          tbl_to_merge |> (IdMap.add rcm1 cm) |> (IdMap.add rcm2 cm)))
    in
    Scanf.Scanning.close_in ic ;
    Outils.remove tmp_commit ;
    ((*gup := *)
      IdMap.add cm 
      (Outils.set_of_list list_pcm) gup ,
     (*gdown := *)
      List.fold_right 
      (fun pcm -> Outils.map_set_add pcm cm) 
      list_pcm gdown ,
     (*tbl_to_merge :=*)
      tbl_to_merge )
  ) (IdMap.empty,IdMap.empty,IdMap.empty) commits


let cmd_graph () =
  Outils.init () ;
  let oc = open_out "branches.dot" in
  fprintf oc "digraph branches_graph{\nrankdir=LR;\n" ;
  let commits = Outils.list_sha !dr_comms in
  let gup,_,tbl_to_merge = make_commit_graph commits in

  (* Attribution des numéros aux commits et aux merges *)
  let n = ref 0 in
  let tbl_num_cm , tbl_num_mg =
    List.fold_left
    (fun (tbl_cm,tbl_mg) cm -> 
      match IdMap.find_opt cm tbl_to_merge with
      | None -> incr n ; (IdMap.add cm !n tbl_cm,tbl_mg)
      | Some cmm -> 
          begin match IdMap.find_opt cmm tbl_mg with
          | None -> incr n ; (tbl_cm,IdMap.add cmm !n tbl_mg) 
          | Some _ -> (tbl_cm,tbl_mg) end
    ) (IdMap.singleton "none" 0, IdMap.empty) commits
  in 

  (* == PRINT DES COMMITS == *)
  fprintf oc "%d [label=\"\"];\n" 0 ; (* tmp *)
  List.iter
  (fun cm ->
    let num =
      match IdMap.find_opt cm tbl_to_merge with
      | None -> IdMap.find cm tbl_num_cm 
      | Some cmm -> IdMap.find cmm tbl_num_mg
    in
    fprintf oc "%d [label=\"\"];\n" num ; (* tmp *)
    match IdSet.elements (IdMap.find cm gup) with
    | [pcm] -> 
        fprintf oc "%d -> %d [label=\"%s\"];\n"
        (IdMap.find pcm tbl_num_cm) num (Outils.short cm)
    | [_;_] -> (* commit tampon de merge *)
        let num_dot = IdMap.find cm tbl_num_mg in
        fprintf oc "%d [label=\"\",shape=point];" num_dot ;
        fprintf oc "%d -> %d [label=\"%s\"];\n" num_dot num (Outils.short cm) ;
    | _ -> failwith "nombre impossible de pcommits"
  ) commits ;

  (* == BRANCHES == *)
  let branches = Outils.list_br () in
  let tbl_br_cm = ref IdMap.empty in
  List.iter
  (fun br -> let cm = Outils.find_commit br in 
    tbl_br_cm := Outils.map_set_add cm br !tbl_br_cm
  ) branches ;

  IdMap.iter 
  (fun cm st_br ->
    let num = IdMap.find cm tbl_num_cm in
    fprintf oc "%d [label=\"%s\",color=%s];\n" num
      (String.concat "\n" (IdSet.elements st_br)) 
      (if IdSet.mem !branch st_br then "red" else "blue")
  ) !tbl_br_cm ;

  fprintf oc "}" ;
  close_out oc ;
  Outils.use_graphviz "branches"
(* ================= *)


(* ===== FORWARD ====== *)
let move_forward br nb_pas =
  let commits = Outils.list_sha !dr_comms in
  let _,gdown,tbl_to_merge = make_commit_graph commits in
  let cm = ref (Outils.find_commit br) in

  let avance cm_next = 
    Branch_mvt.forward br cm_next ;
    begin match IdMap.find_opt cm_next tbl_to_merge with
    | None -> cm := cm_next
    | Some cmm -> Branch_mvt.forward br cmm ; cm := cmm end
  in

  for _ = 1 to nb_pas do
    let st_next = match IdMap.find_opt !cm gdown with
    | None -> IdSet.empty 
    | Some st -> st in
    match IdSet.elements st_next with
    | [] -> ()
    | [cm_next] -> avance cm_next
    | l -> 
      let acm = Array.of_list l in
      let nb_cm = Array.length acm in
      printf
        "The branch %s cannot be moved forward after \"%s...\" \
        because several commits are possible :\n"
        br (Outils.short !cm) ;
      Array.iteri (fun i -> printf "\"%d\" : %s\n" (i+1)) acm ;
      let rec ask_num () =
        let m = read_line () in
        try 
          let n =int_of_string m in
          if 0<n && n <= nb_cm then n
          else ( printf 
             "Out of the range, chose a number between 1 and %d.\n" 
             nb_cm ; ask_num () )
        with | _ -> 
          if m = "stop" then (printf "Stopped.\n"; exit 0)
          else ( printf 
             "Chose a number or write \"stop\" to end the migration here.\
              \n\"mg -branch -graph\" ; \"mg -list_commits\" ; \
              \"mg -cat_commit <sha>\" might help.\n" ; ask_num ())
      in
      avance acm.(ask_num () -1)
  done


(* ===== BACKWARD ====== *)
let move_backward br nb_pas = (* Pas encore de merge, donc simple *)
  let commits = Outils.list_sha !dr_comms in
  let gup,_,_ = make_commit_graph commits in
  let cm = ref (Outils.find_commit br) in

  for _ = 1 to nb_pas do
    print_debug "Commit à back : %s\n" !cm ;
    let st_prev = match IdMap.find_opt !cm gup with
    | None -> IdSet.empty 
    | Some st -> st in

    match IdSet.elements st_prev with
    | [cm_prev] -> Branch_mvt.backward br !cm ; cm := cm_prev
    | [sha1;sha2] -> printf
      "\"%s...\" is a merge commit, to move backward branch %s \
       you need to chose which commit you want to follow :\n\"\
       1\" : %s\nOR\n\"2\" : %s\n"
       (Outils.short !cm) br sha1 sha2 ;
       let cmp = ref (read_line ()) in
       while not (!cmp="stop" || !cmp="1" || !cmp="2") do
        printf "You can write \"stop\" to end the migration here, \
                and use \"mg -cat_commit <sha>\" and/or \"mg -branch \
                -graph\" to thought.\n" ;
        cmp := read_line ()
       done ;
       if !cmp="stop" then (printf "Stopped.\n";exit 0)
       else begin
         let sha = if !cmp="1" then sha1 else sha2 in
         Branch_mvt.backward br sha ; 
         cm := Outils.find_commit br (* parent de sha *)
       end
    | _ -> () (*none commit*)
  done


let cmd_forward nb_pas = 
  Outils.init () ;
  move_forward !branch nb_pas

let cmd_backward nb_pas = 
  Outils.init () ;
  move_backward !branch nb_pas
(* ================= *)




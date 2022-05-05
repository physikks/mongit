
let numerote_old old_ch =
  let nb_num = ref 0 in
  let tbl_num = Hashtbl.create 20 in
  let lines = ref [] in
  begin try while true do
    let l = input_line old_ch in
    match Hashtbl.find_opt tbl_num l with
    | None ->
        Hashtbl.add tbl_num l !nb_num ;
        lines := !nb_num :: !lines ;
        incr nb_num
    | Some num ->
        lines := num :: !lines
  done
  with | End_of_file -> () end ;
  !nb_num , tbl_num , Array.of_list (List.rev !lines)


let indice_new new_ch nb_num tbl_num =
  let t_ind = Array.make nb_num [] in
  let lines = ref [] in
  let i = ref (-1) in
  begin try while true do
    let l = input_line new_ch in
    incr i ;
    match Hashtbl.find_opt tbl_num l with
    | Some num -> 
        t_ind.(num) <- !i :: t_ind.(num) ;
        lines := num :: !lines
    | None -> 
        lines := (-1) :: !lines
  done
  with | End_of_file -> () end ;
  ( Array.map List.rev t_ind ,
    Array.of_list (List.rev !lines) )


let eval_sol t_placeN =
  let lenN = Array.length t_placeN in
  let max_acc = ref (-1) in
  let sum = ref 0 in
  for i = 1 to lenN - 1 do
    if (t_placeN.(i) > !max_acc)
    && (t_placeN.(i) - 1 = t_placeN.(i-1))
    then (max_acc := t_placeN.(i) ; incr sum)
  done ;
  !sum


(* Personne ne retourne en arrière, on prend le premier slot
   et on ne pourra que avancer. *)
let main old_ch new_ch =
  (* Les deux channels ouverts en lecture seule *)
  let nb_num , tbl_num , t_numO = numerote_old old_ch in
  let t_indN , t_numN = indice_new new_ch nb_num tbl_num in
  
  let lenO = Array.length t_numO
  and lenN = Array.length t_numN in 
  let t_placeN = Array.make lenN (-1) in
  let t_placeO = Array.make lenO (-1) in

  (* Etape 1 : tous les lancer *)
  let t_indN' = Array.copy t_indN in
  (* let tbl_dispo = Array.make nb_num [] in *)
  for i_old = 0 to lenO -1 do
    let num = t_numO.(i_old) in
    match t_indN'.(num) with
    | [] -> () 
        (* tbl_dispo.(num) <- i_old :: tbl_dispo.(num) *)
    | next :: q -> 
        t_placeN.(next) <- i_old ;
        t_placeO.(i_old) <- next ;
        t_indN'.(num) <- q
  done ;

  (* Etape 2 : compresser, quitte à pousser *)
  let relance i_new i_old t_placeN t_placeO =
    t_placeO.(i_old) <- -1 ;
    let num = t_numO.(i_old) in
    let i_old = ref i_old in
    List.exists 
     (fun i -> 
        if i < i_new then false
        else if t_placeN.(i) <> -1 then (* On le chasse *)
          ( let i_old' = t_placeN.(i) in
            t_placeO.(i_old') <- -1 ;
            t_placeN.(i) <- !i_old ;
            t_placeO.(!i_old) <- i ;
            i_old := i_old' ;
            false )
        else 
          ( t_placeN.(i) <- !i_old ; 
            t_placeO.(!i_old) <- i ;
            true )
     ) t_indN.(num)
    |> ignore
    (* if not b then tbl_dispo.(num) <- !i_old :: tbl_dispo.(num) *)
  in

  let compress t_placeN t_placeO =
    for i_new = lenN-1 downto 1 do
      let i_old = t_placeN.(i_new) in
      let i_prec = t_placeN.(i_new - 1) in
      if (i_old > 0) && (i_prec <> i_old - 1)
      && (t_numN.(i_new -1) = t_numO.(i_old -1)) 
      then begin
        if i_prec <> -1 then relance i_new i_prec t_placeN t_placeO ;
        t_placeN.(t_placeO.(i_old - 1)) <- -1 ;
        t_placeO.(i_old -1) <- i_new -1 ;
        t_placeN.(i_new -1) <- i_old -1 ;
      end
    done
  in
  compress t_placeN t_placeO ;

  let debut = ref 0 in
  let serie = ref false in
  let sol_act = ref (eval_sol t_placeN) in
  let t_placeN = ref t_placeN
  and t_placeO = ref t_placeO in
  for i_new = 1 to lenN -1 do
    if !t_placeN.(i_new) -1 = !t_placeN.(i_new -1) 
    then (if not !serie then (serie := true ; debut := i_new - 1))
    else if !serie then begin
      let t_placeN_save = Array.copy !t_placeN 
      and t_placeO_save = Array.copy !t_placeO in
      for i = !debut to i_new -1 do
        let i_old = !t_placeN.(i) in
        !t_placeN.(i) <- -1 ;
        relance i_new i_old !t_placeN !t_placeO
      done ;
      let sol_else = eval_sol !t_placeN in
      if !sol_act > sol_else 
      then (t_placeN := t_placeN_save ; t_placeO := t_placeO_save)
      else sol_act := sol_else ;
      serie := false
    end
  done ;

  compress !t_placeN !t_placeO ;

  print_endline (String.concat " " 
    (Array.to_list (Array.map string_of_int !t_placeN)))


let () =
  let oldch = open_in "old.ml"
  and newch = open_in "new.ml" in
  main oldch newch ;
  close_in oldch ; close_in newch
 





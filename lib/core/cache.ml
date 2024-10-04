(* YOCaml a static blog generator.
   Copyright (C) 2024 The Funkyworkers and The YOCaml's developers

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <https://www.gnu.org/licenses/>. *)

module Cache_map = Map.Make (Path)

type entry = {
    hashed_content : string
  ; dynamic_dependencies : Deps.t
  ; last_build_date : int option
}

type t = entry Cache_map.t

let entry ?last_build_date hashed_content dynamic_dependencies =
  { hashed_content; dynamic_dependencies; last_build_date }

let empty = Cache_map.empty
let from_list = Cache_map.of_list

let update cache path ?(deps = Deps.empty) ~now content =
  let entry = entry ~last_build_date:now content deps in
  Cache_map.add path entry cache

let get cache path =
  Option.map
    (fun { hashed_content; dynamic_dependencies; last_build_date } ->
      (hashed_content, dynamic_dependencies, last_build_date))
    (Cache_map.find_opt path cache)

let entry_to_sexp { hashed_content; dynamic_dependencies; last_build_date } =
  let open Sexp in
  let last_build_date =
    last_build_date
    |> Option.map (fun x -> x |> string_of_int |> atom)
    |> Option.to_list
  in
  node
    ([ atom hashed_content; Deps.to_sexp dynamic_dependencies ]
    @ last_build_date)

let last_build_date_from_string lbd =
  match int_of_string_opt lbd with
  | None -> Error (Sexp.Invalid_sexp (Sexp.Atom lbd, "last_build_date"))
  | Some x -> Ok x

let entry_from_sexp sexp =
  let make hashed_content potential_deps last_build_date =
    let entry = entry ?last_build_date hashed_content in
    potential_deps
    |> Deps.from_sexp
    |> Result.map_error (fun _ -> Sexp.Invalid_sexp (sexp, "cache"))
    |> Result.map entry
  in
  match sexp with
  | Sexp.(Node [ Atom hashed_content; potential_deps ]) ->
      make hashed_content potential_deps None
  | Sexp.(Node [ Atom hashed_content; potential_deps; Atom last_build_date ]) ->
      Result.bind (last_build_date_from_string last_build_date) (fun lbd ->
          make hashed_content potential_deps (Some lbd))
  | _ -> Error (Sexp.Invalid_sexp (sexp, "cache"))

let to_sexp cache =
  Cache_map.fold
    (fun key entry acc ->
      let k = Path.to_sexp key in
      let v = entry_to_sexp entry in
      Sexp.node [ k; v ] :: acc)
    cache []
  |> Sexp.node

let key_value_from_sexp sexp =
  match sexp with
  | Sexp.(Node [ key; value ]) ->
      Result.bind (Path.from_sexp key) (fun key ->
          value |> entry_from_sexp |> Result.map (fun value -> (key, value)))
      |> Result.map_error (fun _ -> Sexp.Invalid_sexp (sexp, "cache"))
  | _ -> Error (Sexp.Invalid_sexp (sexp, "cache"))

let from_sexp sexp =
  match sexp with
  | Sexp.(Node entries) ->
      List.fold_left
        (fun acc line ->
          Result.bind acc (fun acc ->
              line |> key_value_from_sexp |> Result.map (fun x -> x :: acc)))
        (Ok []) entries
      |> Result.map Cache_map.of_list
  | _ -> Error (Sexp.Invalid_sexp (sexp, "cache"))

let entry_equal
    {
      hashed_content = hashed_a
    ; dynamic_dependencies = deps_a
    ; last_build_date = lbd_a
    }
    {
      hashed_content = hashed_b
    ; dynamic_dependencies = deps_b
    ; last_build_date = lbd_b
    } =
  String.equal hashed_a hashed_b
  && Deps.equal deps_a deps_b
  && Option.equal Int.equal lbd_a lbd_b

let equal = Cache_map.equal entry_equal

let pp_kv ppf (key, { hashed_content; dynamic_dependencies; last_build_date }) =
  Format.fprintf ppf "%a => deps: @[<v 0>%a@]@hash:%s (%a)" Path.pp key Deps.pp
    dynamic_dependencies hashed_content
    (Format.pp_print_option Format.pp_print_int)
    last_build_date

let pp ppf cache =
  Format.fprintf ppf "Cache [@[<v 0>%a@]]"
    (Format.pp_print_list
       ~pp_sep:(fun ppf () -> Format.fprintf ppf ";@ ")
       pp_kv)
    (Cache_map.to_list cache)

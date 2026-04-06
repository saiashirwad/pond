(lang dune 3.22)

(name pond)

(generate_opam_files true)

(source
 (github saiashirwad/pond))

(authors "Sai Ashirwad")

(license ISC)

(package
 (name pond)
 (synopsis "Structured protocol for remote interfaces")
 (depends
  (ocaml (>= 5.4))
  dune
  eio_main
  yojson))

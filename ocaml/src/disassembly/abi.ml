type mode_t =
  Protected 
 
  
type format_t =
  Pe
| Elf 
      
type segment_t = {
    mutable cs: int;
    mutable ds: int;
    mutable ss: int;
    mutable es: int;
    mutable fs: int;
    mutable gs: int;
  }

let operand_sz = ref 32
let address_sz = ref 32
let segments = {cs = 0 ; ds = 0 ; ss = 0 ; es = 0 ; fs = 0 ; gs = 0}
let stack_width = ref 32


let one = Int64.one
let underflows o = Int64.compare o Int64.zero < 0 
let overflows o sz = Int64.compare o (Int64.sub (Int64.shift_left one sz) one) > 0
    
module M =
struct
    
  (** Segment data type *)
  module Segment = struct
    let cs () = segments.cs
    let ds () = segments.ds
    let ss () = segments.ss
    let es () = segments.es
    let fs () = segments.fs
    let gs () = segments.gs
  end
  module Stack = struct
    let width () = !stack_width
  end

  module Word = struct
    type t 	  = Int64.t * int (* integer is the size in bits *)
    let size w = snd w
    let compare (w1, sz1) (w2, sz2) = 
      let n = Int64.compare w1 w2 in
      if n = 0 then sz1 - sz2 else n

    let default_size ()	= !operand_sz
    let zero sz	  = Int64.zero, sz
    let one sz	  = Int64.one, sz
    let of_int v sz   = Int64.of_int v, sz
    let to_int v      = Int64.to_int (fst v)
    let of_string v n = Int64.of_string v, n
    let sign_extend (v, sz) n = 
      if sz >= n then (v, sz)
      else 
	if Int64.compare v Int64.zero >= 0 then (v, n)
	else 
	  let s = ref v in
	  for i = sz to n-1 do
	    s := Int64.add !s  (Int64.of_int (1 lsl i))
	  done;
	  (!s, n)

      
  end
end

module O =
struct
   
  type t = Int64.t * int (* integer is the size in bits *)
    
  let size o = snd o

  let check o sz = 
    if underflows o then raise (Invalid_argument "negative address");
    if overflows o sz then raise (Invalid_argument "too high address");
    ()
      
  let to_string o = Int64.to_string (fst o)
  let of_string o n = 
    try 
      let a = Int64.of_string o in
      check a n;
      a, n
    with _ -> raise (Invalid_argument "address format ")
      
  let compare (o1, _) (o2, _) = Int64.compare o1 o2
	
  let equal (o1, _) (o2, _) = (Int64.compare o1 o2) = 0
    
  let add_offset (o, n) o' = 
    let off = Int64.add o (Int64.of_int o') in
    check off n;
    off, n
      
  let hash a = Hashtbl.hash a
  let to_word a sz = if sz = snd a then a else failwith "Abi.to_word"
  let default_size () = !address_sz 
  let sub (o1, n1) (o2, n2) =
    if n1 = n2 then Int64.sub o1 o2
    else raise (Invalid_argument "address size")
end
    
module Flat = 
struct
  include M
  module Address = 
  struct
    include O
    module Set = Set.Make(O)
  end
end
  
module Segmented =
struct
  include M
  module Address =
  struct
    module A = struct
      type t = int * O.t
      let default_size () = O.default_size ()
     
      let to_offset (s, o) = O.add_offset o (s lsl 4)

      let check a = 
	let o, sz = to_offset a in
	if underflows o then raise (Invalid_argument "negative address");
	if overflows o sz then raise (Invalid_argument "too high address");
	()

      let to_string (s, (o, _)) = (string_of_int (s lsl 4))  ^ ":" ^ (Int64.to_string o)
      let of_string a n = 
	try
	  let i = String.index a ':' in
	  let s = String.sub a 0 i in
	  let (o: string) = String.sub a (i+1) ((String.length a) - i - 1) in
	  let a' = int_of_string s, O.of_string o n in
	  check a';
	  a'
	with _ -> failwith "Invalid address format"

      let compare a1 a2 = 
	let o1' = to_offset a1 in
	let o2' = to_offset a2 in
	O.compare o1' o2' 

      let equal a1 a2 = O.equal (to_offset a1) (to_offset a2)

      let add_offset (s, o) o' = 
	let off = O.add_offset o o' in
	check (s, off);
	s, off
	  
      let hash a = O.hash (to_offset a)
      let size a = O.size (snd a)
      let to_word a sz = Word.of_string (O.to_string (to_offset a)) sz
      let sub a1 a2 = O.sub (to_offset a1) (to_offset a2)
    end
    include A
    module Set = Set.Make(A)
  end
end
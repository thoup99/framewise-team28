package Utils is
   function Trim (S : String) return String is
      (S (S'First + 1 .. S'Last));
end Utils;
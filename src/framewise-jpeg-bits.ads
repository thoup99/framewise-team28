--  MSB-first entropy reader. No allocation, I/O or unbounded searches.
package Framewise.JPEG.Bits with SPARK_Mode is
   type Reader is private;
   procedure Start (State : out Reader);
   --  Starts at the first byte of the supplied entropy-data slice.

   procedure Read_Bits
     (Data : Byte_Array; State : in out Reader; Count : Natural;
      Value : out Natural; Ok : out Boolean)
     with Pre => Count <= 16;
   --  Use the same Data slice for the lifetime of State. FF00 yields FF.
   --  Any other FFxx, truncation or exhaustion makes failure sticky;
   --  Value is zero on failure, including partially read requests.
   --  Start again on a new slice after handling a restart marker.

   procedure Finish_Interval
     (Data : Byte_Array; State : in out Reader;
      Expected : Byte; Ok : out Boolean);
   --  Discard byte padding and consume exactly the expected restart or EOI.

   function Failed (State : Reader) return Boolean;
   function Marker (State : Reader) return Byte;
   --  Marker returns the terminating marker code, or zero for exhaustion.
   function Consumed (State : Reader) return Natural;
   --  Number of input bytes consumed, including stuffing / marker bytes.
private
   type Reader is record
      Offset    : Natural := 0;
      Current   : Natural range 0 .. 255 := 0;
      Remaining : Natural range 0 .. 8 := 0;
      Error     : Boolean := False;
      Stop_Code : Byte := 0;
   end record;
end Framewise.JPEG.Bits;

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Adi.Core; use Adi.Core;
with Adi.Widget; use Adi.Widget;
with Framewise.Session;
with Timeline_View;

procedure Timeline_View_Tests is
   package FS renames Framewise.Session;
   S : FS.Session;
   R : FS.Response;
   H : Timeline_View.Views.Handle := Timeline_View.Views.New_Widget;
   use type Timeline_View.Views.Handle;
   function Read_Sequence return FS.Sequence_View is (FS.Sequence_Of (S));

   procedure Run (Line : String; Success : Boolean := True) is
   begin
      FS.Execute (S, Line, R);
      pragma Assert (R.Ok = Success, FS.Image (R));
   end Run;

   function Clip_Box (Name : String) return Rectangle is
   begin
      for I in 1 .. Item_Count (+H) loop
         declare
            Label : constant Item := Get_Item (+H, I);
         begin
            if Label.Kind = Text_Item and then To_String (Label.Text_Content) = Name then
               return Get_Item (+H, I - 1).Geometry;
            end if;
         end;
      end loop;
      return (0.0, 0.0, 0.0, 0.0);
   end Clip_Box;

   procedure Rebuild is
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);
   begin
      Timeline_View.Build_Items (V.Ptr.all);
   end Rebuild;

begin
   Set_Geometry (+H, (0.0, 0.0, 1000.0, 450.0));
   declare
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);
   begin
      V.Read_Sequence := Read_Sequence'Unrestricted_Access;
   end;
   Run ("load ../examples/cut.fw");
   Rebuild;
   pragma Assert (Clip_Box ("c1") = (110.0, 34.0, 208.0, 36.0));
   pragma Assert (Clip_Box ("c2") = (382.0, 34.0, 160.0, 36.0));
   pragma Assert (Clip_Box ("c3") = (558.0, 34.0, 256.0, 36.0));
   pragma Assert (Clip_Box ("m1") = (110.0, 82.0, 704.0, 36.0));
   --  A failed engine edit must leave the drawn geometry unchanged.
   Run ("move c3 10", False);
   Rebuild;
   pragma Assert (Clip_Box ("c3").X = 558.0);
   Run ("move c3 13.5");
   Rebuild;
   pragma Assert (Clip_Box ("c3").X = 542.0);
   declare
      V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (H);
      History : constant Natural := FS.History_Length (S);
   begin
      V.Zoom := 64.0;
      V.First_Second := 5.0;
      Timeline_View.Build_Items (V.Ptr.all);
      pragma Assert (FS.History_Length (S) = History);
   end;
   --  c1 begins offscreen and is clipped at the timeline's left edge.
   pragma Assert (Clip_Box ("c1") = (110.0, 34.0, 96.0, 36.0));
   Run ("delete c1");
   Rebuild;
   pragma Assert (Clip_Box ("c1").Width = 0.0);
   Run ("undo");
   Rebuild;
   pragma Assert (Clip_Box ("c1").Width = 96.0);
   while FS.History_Length (S) > 0 loop
      Run ("undo");
   end loop;
   Rebuild;
   pragma Assert (Clip_Box ("m1").Width = 0.0);
   declare
      Base : Widget_Handle := +H;
   begin
      Destroy (Base);
   end;
   Ada.Text_IO.Put_Line ("PASS: timeline geometry, clipping, zoom, session refresh and failed edits");
end Timeline_View_Tests;

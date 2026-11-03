--  Read-only presentation. The reader always returns the current session.
with Adi.Widget;
with Adi.Widget.Extension;
with Framewise.Session;

package Timeline_View is
   type Sequence_Reader is access function return Framewise.Session.Sequence_View;
   type Track_Widget is new Adi.Widget.Widget with record
      Read_Sequence : Sequence_Reader;
      Zoom         : Long_Float := 32.0; -- pixels per second
      First_Second : Long_Float := 0.0;
   end record;

   --  Rebuild labelled clip rectangles from the session without editing it.
   overriding procedure Layout (W : in out Track_Widget) is null;
   overriding procedure Build_Items (W : in out Track_Widget);
   package Views is new Adi.Widget.Extension (Track_Widget);
end Timeline_View;

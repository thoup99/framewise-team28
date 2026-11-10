with Ada.Containers.Vectors;
with Ada.Real_Time; use Ada.Real_Time;
with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget; use Adi.Widget;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Adi.Window; use Adi.Window;
with Editor_Context; use Editor_Context;
with Editor_Styles; use Editor_Styles;

package body Editor_Tooltips is
   use type Labels.Label_Handle;
   use type Boxes.Box_Handle;
   type Hint is record
      Owner : Widget_Handle;
      Text : US.Unbounded_String;
   end record;
   package Hints is new Ada.Containers.Vectors (Positive, Hint);
   Entries : Hints.Vector;
   Tip : Labels.Label_Handle;
   Hovered : Widget_Handle := Null_Handle;
   Since : Time := Clock;
   --  Give users time to move across controls without opening a tooltip.
   Hover_Delay : constant Duration := 1.2;

   procedure Register (Owner : Widget_Handle; Text : String) is
   begin
      if Text'Length > 0 then
         Entries.Append (Hint'(Owner, US.To_Unbounded_String (Text)));
      end if;
   end Register;

   function Hint_For (Owner : Widget_Handle) return String is
   begin
      for H of Entries loop
         if H.Owner = Owner then
            return US.To_String (H.Text);
         end if;
      end loop;
      return "";
   end Hint_For;

   procedure Update (Win : Window_Handle) is
      Target : Widget_Handle := Null_Handle;
   begin
      if Overlay_Count (Win) = 0 then
         for H of Entries loop
            if Has_State (H.Owner, State_Hovered) then
               Target := H.Owner;
               exit;
            end if;
         end loop;
      end if;
      if Target /= Hovered then
         Hovered := Target;
         Since := Clock;
         Set_Visible (+Tip, False);
      end if;
      if Target = Null_Handle then
         Set_Visible (+Tip, False);
      elsif To_Duration (Clock - Since) >= Hover_Delay then
         declare
            G : constant Rectangle := Geometry_In_Window (Target);
            S : constant Size_2D := Get_Size (Win);
         begin
            Labels.Set_Text (Tip, Hint_For (Target));
            Set_Part_Style (+Tip, Main_Part, Style.Base
              ((Floating_Panel_Style with delta Position => Set (Absolute),
                Left => Set_Left (Inset (Px (Float (Pixel_Type'Max (0.0, Pixel_Type'Min (G.X, S.Width - 340.0)))))),
                Top => Set_Top (Inset (Px (Float (Pixel_Type'Min (G.Y + G.Height + 4.0, S.Height - 60.0))))),
                Width => Set (Size (Px (340.0))), Height => Set (Size (Px (54.0))))).Build);
            Set_Visible (+Tip, True);
         end;
      end if;
   end Update;

   procedure Build is
   begin
      Tip := Labels.Create_Handle ("");
      Set_Part_Style (+Tip, Label_Part, Style.Base (Text_Style).Build);
      Set_Visible (+Tip, False);
      Add_Child (+Root, +Tip);
      Connect_Frame (W, Update'Access);
   end Build;
end Editor_Tooltips;

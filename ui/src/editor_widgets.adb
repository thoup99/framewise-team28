with Adi.Core; use Adi.Core;
with Adi.Widget; use Adi.Widget;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Editor_Context; use Editor_Context;
with Editor_Styles; use Editor_Styles;
with Editor_Controller;
with Editor_Tooltips;

package body Editor_Widgets is
   use type Buttons.Button_Handle;
   use type Labels.Label_Handle;

   function Make_Label (Parent : Widget_Handle; Text : String) return Labels.Label_Handle is
      H : constant Labels.Label_Handle := Labels.Create_Handle (Text);
   begin
      Set_Part_Style (+H, Label_Part, Style.Base (Text_Style).Build);
      Add_Child (Parent, +H);
      return H;
   end Make_Label;

   function Make_Button
     (Parent : Widget_Handle; Text : String; Show_Tooltip : Boolean := True)
      return Buttons.Button_Handle
   is
      H : constant Buttons.Button_Handle := Buttons.Create_Handle (Text);
   begin
      Style_Button (H);
      if Show_Tooltip then
         Editor_Tooltips.Register (+H,
           (if Text = "Razor" then "Razor (R): split a clip at the pointer."
            elsif Text = "Undo" then "Undo the last edit (Ctrl+Z)."
            elsif Text = "Delete Clip" then "Delete the selected clip (Delete)."
            elsif Text = "File" then "Project actions: Ctrl+N, Ctrl+O, Ctrl+S, Ctrl+Shift+S."
            elsif Text = "Earlier" then "Scroll the visible timeline five seconds earlier."
            elsif Text = "Later" then "Scroll the visible timeline five seconds later."
            else Text));
      end if;

      Buttons.Connect_Clicked (H, Editor_Controller.Clicked'Access);
      Add_Child (Parent, +H);
      return H;
   end Make_Button;

   procedure Add_Label (Parent : Widget_Handle; Text : String) is
      H : constant Labels.Label_Handle := Make_Label (Parent, Text);
      pragma Unreferenced (H);
   begin
      null;
   end Add_Label;
end Editor_Widgets;

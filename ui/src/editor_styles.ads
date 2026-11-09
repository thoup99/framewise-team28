with Adi.Widget; use Adi.Widget;
with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Editor_Context; use Editor_Context;

package Editor_Styles is
   function Style return Style_Builder renames Adi.Widget_Styles.Create;

   Text_Style : constant Style_Rules :=
     (Color => Set (RGB (215, 225, 239)), Font_Size => Set_Font (Px (14.0)), others => <>);

   Panel_Style : constant Style_Rules :=
     (Display => Set (Flex), Flex_Direction => Set (Column),
      Gap => Set (Gap (Px (8.0))), Padding => Set (CSS_Box (Px (12.0))),
      Background_Color => Set_Bg (RGB (20, 26, 36)), others => <>);

   --  Outline floating surfaces without adding borders to the docked panes.
   Floating_Panel_Style : constant Style_Rules :=
     (Panel_Style with delta
      Border_Width => Set (Border_Width (Px (1.0))),
      Border_Style => Set (Border_Style (Solid)),
      Border_Color => Set (Border_Color (RGB (105, 125, 153))));

   Row_Style : constant Style_Rules :=
     (Display => Set (Flex), Flex_Direction => Set (Row),
      Gap => Set (Gap (Px (6.0))), Flex_Shrink => Set (0.0), others => <>);

   --  Menus are separate overlays and do not inherit the panel theme.
   Popup_Menu_Styles : constant Part_Style_Array :=
     (Main_Part => (Style => Style.Base (Floating_Panel_Style).Build, Enabled => True),
      others => <>);

   function Menu_Item_Styles
     (Highlight_Selection : Boolean := True;
      Dim_Disabled : Boolean := False) return Part_Style_Array;

   --  Keep caret/selection colors shared while callers control input geometry.
   procedure Style_Input_Text (H : Widget_Handle; Selection : Boolean := True);

   procedure Style_Scrollbar (H : Widget_Handle; Highlight_Interactions : Boolean := True);

   Form_Control_Width : constant Float := 360.0;

   procedure Style_Button (H : Buttons.Button_Handle);

   procedure Style_Combo (H : Combos.Combo_Box_Handle);
end Editor_Styles;

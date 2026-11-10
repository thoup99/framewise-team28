with Adi.Window;
package Editor_Preferences is
   type Layout_Settings is record
      Width : Positive := 1280;
      Height : Positive := 850;
      Files_Fraction : Float := 0.31;
      Preview_Fraction : Float := 0.70;
      Maximized : Boolean := False;
      Loaded : Boolean := False;
   end record;

   procedure Load;
   function Current return Layout_Settings;
   function Configuration_Path return String;
   procedure Apply_Panels;
   procedure Capture (Win : Adi.Window.Window_Handle);
   procedure Save;
   --  Preferences are separate from projects and undo history. Invalid or
   --  inaccessible settings never prevent the editor from opening or closing.
end Editor_Preferences;

with Adi.SDL.Events;

package Editor_Console is
   type Command_Origin is (Editor_Action, Console_Command);

   procedure Build;

   function Is_Open return Boolean;

   --  Record even while closed, preserving the command field and its focus.
   procedure Record_Command (Line, Response : String; Origin : Command_Origin);

   procedure Show;

   --  Handle only console-specific keys; ordinary editing stays with the input.
   procedure Handle_Key
     (Scancode : Adi.SDL.Events.SDL_Scancode;
      Repeat : Boolean; Handled : in out Boolean);
end Editor_Console;

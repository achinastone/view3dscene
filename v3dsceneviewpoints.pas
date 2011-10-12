{
  Copyright 2004-2011 Michalis Kamburelis.

  This file is part of "view3dscene".

  "view3dscene" is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  "view3dscene" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with "view3dscene"; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

  ----------------------------------------------------------------------------
}

{ }
unit V3DSceneViewpoints;

interface

uses VectorMath, X3DNodes, CastleWindow, CastleUtils, Classes, CastleClassUtils,
  CastleSceneCore, PrecalculatedAnimation;

{ Return S with newlines replaced with spaces and trimmed to
  sensible number of characters. This is useful when you
  want to use some user-supplied string (e.g. in VRML
  SFString field) in your UI (e.g. as menu or window caption). }
function SForCaption(const S: string): string;

type
  { Menu item referring to a viewpoint.

    Note that in some moments (when we process some events),
    the @link(Viewpoint) instance may no longer be valid:
    we can get T3DSceneCore.ViewpointStack.OnBoundChanged
    when other viewpoint nodes are already freed. }
  TMenuItemViewpoint = class(TMenuItemRadio)
  private
    FViewpoint: TAbstractViewpointNode;
  public
    property Viewpoint: TAbstractViewpointNode read FViewpoint write FViewpoint;
  end;

  { A menu that as children has TMenuItemViewpoint (specific viewpoint)
    or other TMenuViewpointGroup (only with ViewpointGroup <> nil).

    It is associated with a ViewpointGroup node. Unless it's a root node
    (the one descending from TMenuViewpoints), then ViewpointGroup = nil. }
  TMenuViewpointGroup = class(TMenu)
  private
    FViewpointGroup: TViewpointGroupNode;
  public
    property ViewpointGroup: TViewpointGroupNode read FViewpointGroup write FViewpointGroup;
    { Find a children TMenuViewpointGroup associated with given AViewpointGroup
      node. }
    function FindGroup(AViewpointGroup: TViewpointGroupNode): TMenuViewpointGroup;
  end;

  TMenuViewpoints = class(TMenuViewpointGroup)
  private
    { When nil, then BoundViewpoint is always nil }
    ViewpointsRadioGroup: TMenuItemRadioGroup;

    { Used only during AddViewpoint callback }
    SceneBoundViewpoint: TAbstractViewpointNode;
    AddViewpointGroups: TX3DNodeList;

    procedure AddViewpoint(
      Node: TX3DNode; StateStack: TX3DGraphTraverseStateStack;
      ParentInfo: PTraversingInfo; var TraverseIntoChildren: boolean);
    function GetBoundViewpoint: TMenuItemViewpoint;
    procedure SetBoundViewpoint(const Value: TMenuItemViewpoint);
  public
    { Currently bound viewpoint (@nil if none),
      used to make appropriate menu item "checked".

      Note: we cannot make this of TAbstractViewpointNode,
      because the same viewpoint node may be USEd many times
      within a single scene. }
    property BoundViewpoint: TMenuItemViewpoint
      read GetBoundViewpoint write SetBoundViewpoint;

    { Recalculate menu contents.
      Special value Scene = @nil means no scene is loaded, so no
      viewpoint nodes exist. }
    procedure Recalculate(Scene: T3DSceneCore);

    function ItemOf(Viewpoint: TAbstractViewpointNode): TMenuItemViewpoint;
  end;

var
  Viewpoints: TMenuViewpoints;

{ Parse --viewpoint command-line option, if exists. }
procedure ViewpointsParseParameters;

{ Apply --viewpoint command-line option to the next loaded scenes. }
procedure SetInitialViewpoint(SceneAnimation: T3DPrecalculatedAnimation;
  const EnableNonStandardValue: boolean);

implementation

uses SysUtils, CastleStringUtils, CastleParameters;

function SForCaption(const S: string): string;
begin
  Result := SCompressWhiteSpace(S);
  if Length(Result) > 50 then
    Result := Copy(Result, 1, 50) + '...';
end;

function TMenuViewpointGroup.FindGroup(
  AViewpointGroup: TViewpointGroupNode): TMenuViewpointGroup;
var
  I: Integer;
begin
  for I := 0 to EntriesCount - 1 do
    if (Entries[I] is TMenuViewpointGroup) and
       (TMenuViewpointGroup(Entries[I]).ViewpointGroup = AViewpointGroup) then
      Exit(TMenuViewpointGroup(Entries[I]));
  Result := nil;
end;

const
  { We don't add more menu item entries for viewpoints. }
  MaxMenuItems = 20;

procedure TMenuViewpoints.AddViewpoint(
  Node: TX3DNode; StateStack: TX3DGraphTraverseStateStack;
  ParentInfo: PTraversingInfo; var TraverseIntoChildren: boolean);

  { Nice menu item caption for TAbstractViewpointNode or TViewpointGroupNode }
  function ViewpointToMenuCaption(const ItemIndex: Integer; Node: TX3DNode): string;
  var
    Description: string;
  begin
    if ItemIndex < 10 then
      Result := '_';
    Result += IntToStr(ItemIndex) + ': ';

    Description := '';

    if Node is TAbstractX3DViewpointNode then
    begin
      Description := SQuoteMenuEntryCaption(
        SForCaption(TAbstractX3DViewpointNode(Node).FdDescription.Value));
    end else
    if Node is TViewpointGroupNode then
    begin
      Description := SQuoteMenuEntryCaption(
        SForCaption(TViewpointGroupNode(Node).FdDescription.Value));
    end;

    { if node doesn't have a "description" field, or it's left empty,
      use node name }
    if Description = '' then
      Description := SQuoteMenuEntryCaption(Node.NodeName);

    { if even the node name is empty, just write node type. }
    if Description = '' then
      Description := SQuoteMenuEntryCaption(Node.NodeTypeName);

    Result += Description;
  end;

  { Scan ParentInfo information for TViewpointGroupNode.

    If every ViewpointGroup has "displayed" = true, then we
    fill the AddViewpointGroups list with found ViewpointGroup nodes.
    Ordered from top-most (so the order is similar to submenus order,
    and reversed than order on ParentInfo list).

    If some ViewpointGroup on the way has "displayed" = false, then
    we return false and leave AddViewpointGroups in undefined state. }
  function GetParentViewpointGroups(AddViewpointGroups: TX3DNodeList): boolean;
  var
    Info: PTraversingInfo;
  begin
    AddViewpointGroups.Count := 0;
    Result := true;

    Info := ParentInfo;
    while Info <> nil do
    begin
      if Info^.Node is TViewpointGroupNode then
      begin
        if not TViewpointGroupNode(Info^.Node).FdDisplayed.Value then
          Exit(false);
        AddViewpointGroups.Insert(0, Info^.Node);
      end;
      Info := Info^.ParentInfo;
    end;
  end;

  { For all the ViewpointGroup gathered in AddViewpointGroups,
    create (or find existing) appropriate submenu.
    Returns the final menu where you should directly add your viewpoint. }
  function CreateParentViewpointGroups(AddViewpointGroups: TX3DNodeList): TMenuViewpointGroup;
  var
    Group: TViewpointGroupNode;
    I: Integer;
    NewResult: TMenuViewpointGroup;
  begin
    Result := Self;
    for I := 0 to AddViewpointGroups.Count - 1 do
    begin
      Group := AddViewpointGroups[I] as TViewpointGroupNode;
      NewResult := Result.FindGroup(Group);
      if NewResult = nil then
      begin
        NewResult := TMenuViewpointGroup.Create(
          ViewpointToMenuCaption(Result.EntriesCount, Group));
        NewResult.ViewpointGroup := Group;
        Result.Append(NewResult);
      end;
      Result := NewResult;
    end;
  end;

var
  ItemIndex: Integer;
  S: string;
  MenuItem: TMenuItemViewpoint;
  Group: TMenuViewpointGroup;
begin
  if not GetParentViewpointGroups(AddViewpointGroups) then Exit;

  Group := CreateParentViewpointGroups(AddViewpointGroups);

  ItemIndex := Group.EntriesCount;
  if ItemIndex < MaxMenuItems then
  begin
    S := ViewpointToMenuCaption(ItemIndex, Node);

    MenuItem := TMenuItemViewpoint.Create(S, 300, SceneBoundViewpoint = Node, false);
    MenuItem.Viewpoint := Node as TAbstractViewpointNode;

    { If we have found the currently bound node (and made this menu item
      selected), then reset SceneBoundViewpoint to nil. This way the first
      encountered viewpoint node matching Scene.ViewpointStack.Top will be
      selected.

      TODO: This isn't really 100% correct, but Scene simply doesn't tell
      us which instance of viewpoint node is actually bound. }
    if SceneBoundViewpoint = Node then
      SceneBoundViewpoint := nil;

    if ViewpointsRadioGroup = nil then
      ViewpointsRadioGroup := MenuItem.Group else
      MenuItem.Group := ViewpointsRadioGroup;

    Group.Append(MenuItem);
  end;
end;

procedure TMenuViewpoints.Recalculate(Scene: T3DSceneCore);
begin
  MenuUpdateBegin;
  EntriesDeleteAll;

  ViewpointsRadioGroup := nil;

  if (Scene <> nil) and
     (Scene.RootNode <> nil) then
  begin
    SceneBoundViewpoint := Scene.ViewpointStack.Top as TAbstractViewpointNode;
    AddViewpointGroups := TX3DNodeList.Create(false);

    Scene.RootNode.Traverse(TAbstractViewpointNode, @AddViewpoint);

    SceneBoundViewpoint := nil; //< just for safety
    FreeAndNil(AddViewpointGroups);
  end;

  Append(TMenuSeparator.Create);
  Append(TMenuItem.Create('Default VRML 1.0 viewpoint', 51));
  Append(TMenuItem.Create('Default VRML 2.0 (and X3D) viewpoint', 52));
  Append(TMenuSeparator.Create);
  Append(TMenuItem.Create('Calculated viewpoint to see the scene (+Y up, -Z dir)', 53));
  Append(TMenuItem.Create('Calculated viewpoint to see the scene (+Y up, +Z dir)', 54));
  Append(TMenuItem.Create('Calculated viewpoint to see the scene (+Y up, -X dir)', 55));
  Append(TMenuItem.Create('Calculated viewpoint to see the scene (+Y up, +X dir)', 56));
  Append(TMenuSeparator.Create);
  Append(TMenuItem.Create('Calculated viewpoint to see the scene (+Z up, -X dir)', 57));
  Append(TMenuItem.Create('Calculated viewpoint to see the scene (+Z up, +X dir)', 58));
  Append(TMenuItem.Create('Calculated viewpoint to see the scene (+Z up, -Y dir)', 59));
  Append(TMenuItem.Create('Calculated viewpoint to see the scene (+Z up, +Y dir)', 60));

  MenuUpdateEnd;
end;

function TMenuViewpoints.GetBoundViewpoint: TMenuItemViewpoint;
begin
  if ViewpointsRadioGroup <> nil then
    Result := ViewpointsRadioGroup.Selected as TMenuItemViewpoint else
    Result := nil; //< then no viewpoints exist
end;

procedure TMenuViewpoints.SetBoundViewpoint(const Value: TMenuItemViewpoint);
begin
  if ViewpointsRadioGroup <> nil then
    ViewpointsRadioGroup.Selected := Value else
    { When no viewpoints exist, BoundViewpoint is always nil }
    Assert(Value = nil);
end;

function TMenuViewpoints.ItemOf(Viewpoint: TAbstractViewpointNode): TMenuItemViewpoint;
var
  I: Integer;
begin
  if ViewpointsRadioGroup <> nil then
    for I := 0 to ViewpointsRadioGroup.Count - 1 do
      if TMenuItemViewpoint(ViewpointsRadioGroup.Items[I]).Viewpoint = Viewpoint then
        Exit(TMenuItemViewpoint(ViewpointsRadioGroup.Items[I]));
  Result := nil;
end;

{ command-line options ------------------------------------------------------- }

var
  UseInitialViewpoint: boolean = false;
  InitialViewpointIndex: Integer;
  InitialViewpointName: string;

procedure OptionProc(OptionNum: Integer; HasArgument: boolean;
  const Argument: string; const SeparateArgs: TSeparateArgs; Data: Pointer);
begin
  Assert(OptionNum = 0);
  UseInitialViewpoint := true;
  InitialViewpointIndex := 0;
  InitialViewpointName := '';

  { calculate InitialViewpoint* }
  try
    InitialViewpointIndex := StrToInt(Argument);
  except on EConvertError do
    InitialViewpointName := Argument;
  end;
end;

procedure ViewpointsParseParameters;
const
  Options: array[0..0]of TOption =
  ((Short:#0; Long:'viewpoint'; Argument: oaRequired));
begin
  Parameters.Parse(Options, @OptionProc, nil, true);
end;

procedure SetInitialViewpoint(SceneAnimation: T3DPrecalculatedAnimation;
  const EnableNonStandardValue: boolean);
begin
  if EnableNonStandardValue and UseInitialViewpoint then
  begin
    UseInitialViewpoint := false;
    SceneAnimation.InitialViewpointIndex := InitialViewpointIndex;
    SceneAnimation.InitialViewpointName := InitialViewpointName;
  end else
  begin
    SceneAnimation.InitialViewpointIndex := 0;
    SceneAnimation.InitialViewpointName := '';
  end;
end;

initialization
  Viewpoints := TMenuViewpoints.Create('Jump to Viewpoint');
end.

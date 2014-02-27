defmodule Yugioh.Core.BattleCore do
  require Lager

  def send_message player_pid,message,params do
    message_data = Yugioh.Proto.PT12.write(message,params)
    send player_pid,{:send,message_data}
  end  

  def hide_handcards battle_info do
    cards_size = length battle_info.handcards    
    battle_info.handcards Enum.take(Stream.cycle([0]),cards_size)
  end

  def is_operator? player_id,BattleData[operator_id: operator_id] do
    operator_id == player_id
  end

  def get_operator_battle_info BattleData[operator_id: operator_id,player1_id: player1_id,player2_id: player2_id,
                                player1_battle_info: player1_battle_info,player2_battle_info: player2_battle_info] do
    case operator_id do
      ^player1_id ->
        player1_battle_info
      ^player2_id ->
        player2_battle_info
    end
  end

  def get_operator_atom BattleData[operator_id: operator_id,player1_id: player1_id,player2_id: player2_id] do
    case operator_id do
      ^player1_id ->
        :player1_battle_info
      ^player2_id ->
        :player2_battle_info
    end
  end

  def get_player_battle_info player_id,BattleData[operator_id: operator_id,player1_id: player1_id,player2_id: player2_id,
                                player1_battle_info: player1_battle_info,player2_battle_info: player2_battle_info] do
    case player_id do
      ^player1_id ->
        player1_battle_info
      ^player2_id ->
        player2_battle_info
    end
  end

  def get_player_atom player_id,BattleData[operator_id: operator_id,player1_id: player1_id,player2_id: player2_id] do
    case player_id do
      ^player1_id ->
        :player1_battle_info
      ^player2_id ->
        :player2_battle_info
    end
  end


  def get_opponent_player_id BattleData[operator_id: operator_id,player1_id: player1_id,player2_id: player2_id] do
    case operator_id do
      ^player1_id->
        player2_id
      ^player2_id->
        player1_id
    end
  end

  def get_opponent_player_atom BattleData[operator_id: operator_id,player1_id: player1_id,player2_id: player2_id] do
    case operator_id do
      ^player1_id ->
        :player2_battle_info
      ^player2_id ->
        :player1_battle_info
    end
  end

  def get_opponent_player_battle_info BattleData[operator_id: operator_id,player1_id: player1_id,player2_id: player2_id,
  player1_battle_info: player1_battle_info,player2_battle_info: player2_battle_info] do
    case operator_id do
      ^player1_id ->
        player2_battle_info
      ^player2_id ->
        player1_battle_info
    end
  end
  
  
  # 0 mean that we have not start our battle,we start the new turn after we collected two battle load finish message
  def get_new_turn_operator_id(battle_data = BattleData[operator_id: operator_id,turn_count: turn_count,player1_id: player1_id,player2_id: player2_id]) 
  when turn_count == 0 do
    operator_id
  end

  def get_new_turn_operator_id(battle_data) do
    get_opponent_player_id battle_data
  end  

  def get_presentation_operations presentation do
    case presentation do
      :attack ->
        [:change_to_defense_present_operation]
      :defense_down ->
        [:reverse_operation]
      :defense_up ->
        [:change_to_attack_present_operation]
    end
  end
  

  def get_handcard_operations card_id,monster_summoned_count do
    card_level = Card.get(card_id).level
    case card_level do
      x when x==5 or x==6 ->        
        if monster_summoned_count >=1 do
          [:summon_operation,:place_operation]
        else
          []
        end
      x when x==7 or x==8 ->
        if monster_summoned_count >=2 do
          [:summon_operation,:place_operation]
        else
          []
        end
      x when x>8 ->
        if monster_summoned_count >=3 do
          [:summon_operation,:place_operation]
        else
          []
        end
      _ ->
        [:summon_operation,:place_operation]
    end
  end

  def get_handcard_normal_operations _,5 do
    []
  end

  def get_graveyard_params_string battle_data do
    player1_graveyard_card_id = if(Enum.empty?(battle_data.player1_battle_info.graveyardcards)) do
      0
    else
      hd(battle_data.player1_battle_info.graveyardcards)
    end
    player2_graveyard_card_id = if(Enum.empty?(battle_data.player2_battle_info.graveyardcards)) do
      0
    else
      hd(battle_data.player2_battle_info.graveyardcards)
    end
    "#{battle_data.player1_id};#{player1_graveyard_card_id};#{battle_data.player2_id};#{player2_graveyard_card_id}"
  end

  def create_card_presentation_change_effect card_id,new_presentation,player_id,scene_type,index do
    attack_effect = Effect.new(type: :card_presentation_change_effect,
      params: "#{card_id};#{Yugioh.Proto.PT12.presentation_id_from(new_presentation)}",
      targets: [Target[player_id: player_id,scene_type: scene_type,index: index]])
  end
  
  def create_attack_card_effect attack_player_id,attack_card_index,defense_player_id,defense_card_index,
  damage_player_id,hp_damage do
    attack_target = Target[player_id: attack_player_id,scene_type: :monster_card_zone,index: attack_card_index]
    defense_target = Target[player_id: defense_player_id,scene_type: :monster_card_zone,index: defense_card_index]
    Effect.new(type: :attack_effect,
      params: "#{attack_player_id};#{defense_player_id};#{damage_player_id};#{hp_damage}",
      targets: [attack_target,defense_target])        
  end

  def create_attack_player_effect attack_player_id,attack_card_index,defense_player_id,hp_damage do
    attack_target = Target[player_id: attack_player_id,scene_type: :monster_card_zone,index: attack_card_index]
    defense_target = Target[player_id: defense_player_id,scene_type: :player_zone,index: 0]
    Effect.new(type: :attack_effect,
      params: "#{attack_player_id};#{defense_player_id};#{defense_player_id};#{hp_damage}",
      targets: [attack_target,defense_target])
  end

  def create_move_to_graveyard_effect destroy_cards,battle_data do
    targets = Enum.map destroy_cards,fn({player_id,card_id,card_index})->
      Target[player_id: player_id,scene_type: :monster_card_zone,index: card_index]
    end
    Effect.new(type: :move_to_graveyard_effect,
        params: get_graveyard_params_string(battle_data),
        targets: targets)
  end
  
  # already_attacked
  def attack_card_caculation(_player,_opponent_player,Monster[attacked: attacked],_opponent_monster,battle_data) 
  when attacked == true do
    {:already_attacked,battle_data,[]}
  end

  # defense_card_cant_attack
  def attack_card_caculation(_player,_opponent_player,Monster[presentation: presentation],_defense_monster,battle_data)
  when presentation != :attack do
    {:defense_card_cant_attack,battle_data,[]}
  end  

  # attack a > b
  def attack_card_caculation({player_id,player_atom,player_battle_info,source_card_index},
    {opponent_player_id,opponent_player_atom,opponent_player_battle_info,target_card_index},
    attack_monster = Monster[presentation: :attack,attack: attack_monster_attack],
    opponent_monster = Monster[presentation: :attack,attack: opponent_monster_attack],
    battle_data) when attack_monster_attack > opponent_monster_attack do
    destroy_cards = [{opponent_player_id,opponent_monster.id,target_card_index}]
    opponent_graveyardcards = [opponent_monster.id|opponent_player_battle_info.graveyardcards]
    opponent_monster_card_zone = Dict.delete opponent_player_battle_info.monster_card_zone,target_card_index
    damage_player_id = opponent_player_id

    hp_damage = attack_monster_attack - opponent_monster_attack
    if hp_damage>opponent_player_battle_info.curhp do
      hp_damage = opponent_player_battle_info.curhp
    end

    opponent_curhp = opponent_player_battle_info.curhp - hp_damage
    opponent_player_battle_info = opponent_player_battle_info.update(curhp: opponent_curhp,
      monster_card_zone: opponent_monster_card_zone,graveyardcards: opponent_graveyardcards)
    
    player_battle_info = player_battle_info.monster_card_zone 
    |> Dict.put(source_card_index,attack_monster.attacked(true)) 
    |> player_battle_info.monster_card_zone
    
    battle_data = battle_data.update([{opponent_player_atom,opponent_player_battle_info},{player_atom,player_battle_info}])

    if opponent_curhp <= 0 do
      send self,:battle_end
    end
    attack_card_effect = create_attack_card_effect(player_id,source_card_index,opponent_player_id,target_card_index,
      damage_player_id,hp_damage)
    move_to_graveyard_effect = create_move_to_graveyard_effect(destroy_cards,battle_data)
    {:ok,battle_data,[attack_card_effect,move_to_graveyard_effect]}
  end

  # attack a < b
  def attack_card_caculation({player_id,player_atom,player_battle_info,source_card_index},
    {opponent_player_id,opponent_player_atom,opponent_player_battle_info,target_card_index},
    attack_monster = Monster[presentation: :attack,attack: attack_monster_attack],
    opponent_monster = Monster[presentation: :attack,attack: opponent_monster_attack],
    battle_data) when attack_monster_attack < opponent_monster_attack do
    destroy_cards = [{player_id,attack_monster.id,source_card_index}]
    graveyardcards = [attack_monster.id|player_battle_info.graveyardcards]
    monster_card_zone = Dict.delete player_battle_info.monster_card_zone,source_card_index
    damage_player_id = player_id
    hp_damage = opponent_monster.attack - attack_monster.attack
    if hp_damage>player_battle_info.curhp do
      hp_damage = player_battle_info.curhp
    end
    curhp = player_battle_info.curhp - hp_damage    
    if curhp <= 0 do
      send self,:battle_end
    end
    player_battle_info = player_battle_info.update(curhp: curhp,monster_card_zone: monster_card_zone,graveyardcards: graveyardcards)
    battle_data = battle_data.update([{player_atom,player_battle_info}])
    attack_card_effect = create_attack_card_effect(player_id,source_card_index,opponent_player_id,target_card_index,
      damage_player_id,hp_damage)
    move_to_graveyard_effect = create_move_to_graveyard_effect(destroy_cards,battle_data)
    {:ok,battle_data,[attack_card_effect,move_to_graveyard_effect]}
  end

  # attack a == b
  def attack_card_caculation({player_id,player_atom,player_battle_info,source_card_index},
    {opponent_player_id,opponent_player_atom,opponent_player_battle_info,target_card_index},
    attack_monster = Monster[presentation: :attack,attack: attack_monster_attack],
    opponent_monster = Monster[presentation: :attack,attack: opponent_monster_attack],
    battle_data) when attack_monster_attack == opponent_monster_attack do
    destroy_cards = [{player_id,attack_monster.id,source_card_index},{opponent_player_id,opponent_monster.id,target_card_index}]
    graveyardcards = [attack_monster.id|player_battle_info.graveyardcards]
    opponent_graveyardcards = [opponent_monster.id|opponent_player_battle_info.graveyardcards]
    monster_card_zone = Dict.delete player_battle_info.monster_card_zone,source_card_index
    opponent_monster_card_zone = Dict.delete opponent_player_battle_info.monster_card_zone,target_card_index
    player_battle_info = player_battle_info.update(monster_card_zone: monster_card_zone,graveyardcards: graveyardcards)
    opponent_player_battle_info = opponent_player_battle_info.update(monster_card_zone: opponent_monster_card_zone,graveyardcards: opponent_graveyardcards)
    battle_data = battle_data.update([{opponent_player_atom,opponent_player_battle_info},{player_atom,player_battle_info}])
    attack_card_effect = create_attack_card_effect(player_id,source_card_index,opponent_player_id,target_card_index,
      0,0)
    move_to_graveyard_effect = create_move_to_graveyard_effect(destroy_cards,battle_data)
    {:ok,battle_data,[attack_card_effect,move_to_graveyard_effect]}
  end

  # defense a > b
  def attack_card_caculation({player_id,player_atom,player_battle_info,source_card_index},
    {opponent_player_id,opponent_player_atom,opponent_player_battle_info,target_card_index},
    attack_monster = Monster[presentation: :attack,attack: attack_monster_attack],
    opponent_monster = Monster[presentation: defense_state,defense: opponent_monster_defense],
    battle_data) when attack_monster_attack > opponent_monster_defense do
    destroy_cards = [{opponent_player_id,opponent_monster.id,target_card_index}]
    opponent_graveyardcards = opponent_player_battle_info.graveyardcards++[opponent_monster.id]
    opponent_monster_card_zone = Dict.delete opponent_player_battle_info.monster_card_zone,target_card_index
    opponent_player_battle_info = opponent_player_battle_info.update(
      monster_card_zone: opponent_monster_card_zone,graveyardcards: opponent_graveyardcards)
    monster_card_zone = Dict.put player_battle_info.monster_card_zone,source_card_index,attack_monster.attacked(true)
    player_battle_info = player_battle_info.monster_card_zone monster_card_zone
    battle_data = battle_data.update([{opponent_player_atom,opponent_player_battle_info},{player_atom,player_battle_info}])
    attack_card_effect = create_attack_card_effect(player_id,source_card_index,opponent_player_id,target_card_index,
      0,0)
    move_to_graveyard_effect = create_move_to_graveyard_effect(destroy_cards,battle_data)
    effects = if defense_state == :defense_down do
      card_presentation_change_effect =  create_card_presentation_change_effect(opponent_monster.id,:defense_up,opponent_player_id,:monster_card_zone,target_card_index)
      [attack_card_effect,card_presentation_change_effect,move_to_graveyard_effect]
    else
      [attack_card_effect,move_to_graveyard_effect]
    end
    {:ok,battle_data,effects}
  end

  # defense a < b
  def attack_card_caculation({player_id,player_atom,player_battle_info,source_card_index},
    {opponent_player_id,opponent_player_atom,opponent_player_battle_info,target_card_index},
    attack_monster = Monster[presentation: :attack,attack: attack_monster_attack],
    opponent_monster = Monster[presentation: defense_state,defense: opponent_monster_defense],
    battle_data) when attack_monster_attack < opponent_monster_defense do
    hp_damage = opponent_monster_defense - attack_monster_attack
    if hp_damage>player_battle_info.curhp do
      hp_damage = player_battle_info.curhp
    end
    damage_player_id = player_id
    curhp = player_battle_info.curhp - hp_damage
    monster_card_zone = Dict.put player_battle_info.monster_card_zone,source_card_index,attack_monster.attacked(true)
    player_battle_info = player_battle_info.update(monster_card_zone: monster_card_zone,curhp: curhp)
    if defense_state == :defense_down do
      opponent_monster_card_zone = Dict.put opponent_player_battle_info.monster_card_zone,target_card_index,opponent_monster.presentation(:defense_up)
      opponent_player_battle_info = opponent_player_battle_info.monster_card_zone opponent_monster_card_zone
      battle_data = battle_data.update([{player_atom,player_battle_info},
        {opponent_player_atom,opponent_player_battle_info}])      
    else
      battle_data = battle_data.update([{player_atom,player_battle_info}])
    end
    if curhp <= 0 do
      send self,:battle_end
    end    
    attack_card_effect = create_attack_card_effect(player_id,source_card_index,opponent_player_id,target_card_index,
      damage_player_id,hp_damage)
    move_to_graveyard_effect = create_move_to_graveyard_effect([],battle_data)
    effects = if defense_state == :defense_down do
      card_presentation_change_effect =  create_card_presentation_change_effect(opponent_monster.id,:defense_up,opponent_player_id,:monster_card_zone,target_card_index)
      [attack_card_effect,card_presentation_change_effect,move_to_graveyard_effect]
    else
      [attack_card_effect,move_to_graveyard_effect]
    end
    {:ok,battle_data,effects}
  end

  # defense a == b
  def attack_card_caculation({player_id,player_atom,player_battle_info,source_card_index},
    {opponent_player_id,opponent_player_atom,opponent_player_battle_info,target_card_index},
    attack_monster = Monster[presentation: :attack,attack: attack_monster_attack],
    opponent_monster = Monster[presentation: defense_state,defense: opponent_monster_defense],
    battle_data) when attack_monster_attack == opponent_monster_defense do
    monster_card_zone = Dict.put player_battle_info.monster_card_zone,source_card_index,attack_monster.attacked(true)
    player_battle_info = player_battle_info.update(monster_card_zone: monster_card_zone)
    if defense_state == :defense_down do
      opponent_monster_card_zone = Dict.put opponent_player_battle_info.monster_card_zone,target_card_index,opponent_monster.presentation(:defense_up)
      opponent_player_battle_info = opponent_player_battle_info.monster_card_zone opponent_monster_card_zone
      battle_data = battle_data.update([{opponent_player_atom,opponent_player_battle_info},{player_atom,player_battle_info}])
    else
      battle_data = battle_data.update([{player_atom,player_battle_info}])
    end
    Lager.debug "battle_data [~p]",battle_data
    attack_card_effect = create_attack_card_effect(player_id,source_card_index,opponent_player_id,target_card_index,
      0,0)
    move_to_graveyard_effect = create_move_to_graveyard_effect([],battle_data)
    effects = if defense_state == :defense_down do
      card_presentation_change_effect =  create_card_presentation_change_effect(opponent_monster.id,:defense_up,opponent_player_id,:monster_card_zone,target_card_index)
      [attack_card_effect,card_presentation_change_effect,move_to_graveyard_effect]
    else
      [attack_card_effect,move_to_graveyard_effect]
    end
    {:ok,battle_data,effects}
  end

  
  def attack_card(player_id,source_card_index,opponent_card_index,
    battle_data = BattleData[player1_id: player1_id,player2_id: player2_id]) do

    player = {_,_,player_battle_info,_} = {battle_data.operator_id,get_operator_atom(battle_data),
    get_operator_battle_info(battle_data),source_card_index}

    opponent_player = {_,_,opponent_player_battle_info,_} = {get_opponent_player_id(battle_data),get_opponent_player_atom(battle_data),
    get_opponent_player_battle_info(battle_data),opponent_card_index}
    
    attack_monster = Dict.get player_battle_info.monster_card_zone,source_card_index
    opponent_monster = Dict.get opponent_player_battle_info.monster_card_zone,opponent_card_index

    {result,battle_data,effects} =attack_card_caculation player,opponent_player,attack_monster,opponent_monster,battle_data
    
    send_message battle_data.player1_battle_info.player_pid,:effects,effects
    send_message battle_data.player2_battle_info.player_pid,:effects,effects
    {result,battle_data}
  end

  def attack_player player_id,source_card_index,battle_data = BattleData[player1_id: player1_id,player2_id: player2_id] do

    {player_id,player_atom,player_battle_info} = {battle_data.operator_id,get_operator_atom(battle_data),
    get_operator_battle_info(battle_data)}

    {opponent_player_id,opponent_player_atom,opponent_player_battle_info} = {get_opponent_player_id(battle_data),get_opponent_player_atom(battle_data),
    get_opponent_player_battle_info(battle_data)}
    
    attack_monster = Dict.get player_battle_info.monster_card_zone,source_card_index    
    result = :ok
    if Dict.size(opponent_player_battle_info.monster_card_zone)!=0 do
      result = :attack_directly_invalid
    end      
    if result == :ok do
      hp_damage = attack_monster.attack
      if hp_damage>opponent_player_battle_info.curhp do
        hp_damage = opponent_player_battle_info.curhp
      end

      opponent_player_battle_info = opponent_player_battle_info.curhp(opponent_player_battle_info.curhp - hp_damage)
      player_battle_info = player_battle_info.monster_card_zone(Dict.put(player_battle_info.monster_card_zone,source_card_index,attack_monster.attacked(true)))
       
      battle_data = battle_data.update([{opponent_player_atom,opponent_player_battle_info},
          {player_atom,player_battle_info}])
      if opponent_player_battle_info.curhp <= 0 do
        send self,:battle_end
      end
      attack_effect = create_attack_player_effect player_id,source_card_index,opponent_player_id,hp_damage
      send_message battle_data.player1_battle_info.player_pid,:effects,[attack_effect]
      send_message battle_data.player2_battle_info.player_pid,:effects,[attack_effect]
    end    
    {result,battle_data}
  end  
end
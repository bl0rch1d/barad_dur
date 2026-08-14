class ActivityController < ApplicationController
  ROOM = "ALG-215".freeze

  def show
    @messages = ChatMessage.in_room(ROOM).to_a
    @events = Event.recent.limit(30).to_a
  end
end

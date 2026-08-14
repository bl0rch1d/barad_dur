class GatesController < ApplicationController
  def approve
    gate = Gate.find(params[:id])
    PipelineEngine.approve_gate!(gate)
    back
  end
end

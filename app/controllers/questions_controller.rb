class QuestionsController < ApplicationController
  def answer
    question = Question.find(params[:id])
    option = params[:option].to_s
    PipelineEngine.answer_question!(question, option) if question.options.include?(option)
    back
  end
end

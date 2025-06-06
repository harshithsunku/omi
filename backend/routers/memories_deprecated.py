# Memories are now conversations, and the routes are now in the routes/conversation.py file

# MIGRATE: This file is deprecated and will be removed in the future.
# Please refer to the routes/conversation.py file for the latest routes.
# This file is only used by the old versions of the app

from fastapi import APIRouter, Depends, HTTPException

import database.conversations as conversations_db
import database.memories as memories_db
import database.redis_db as redis_db
from database.vector_db import delete_vector
from models.conversation import Conversation
from models.conversation import *
from routers.speech_profile import expand_speech_profile
from utils.conversations.process_conversation import process_conversation, retrieve_in_progress_conversation
from utils.conversations.search import search_conversations
from utils.other import endpoints as auth
from utils.other.storage import get_conversation_recording_if_exists, \
    delete_additional_profile_audio, delete_speech_sample_for_people
from utils.plugins import trigger_external_integrations

router = APIRouter()


def _get_memory_by_id(uid: str, memory_id: str) -> dict:
    memory = conversations_db.get_conversation(uid, memory_id)
    if memory is None or memory.get('deleted', False):
        raise HTTPException(status_code=404, detail="Memory not found")
    return memory


@router.post("/v2/memories", response_model=CreateMemoryResponse, tags=['memories'])
def process_in_progress_memory(uid: str = Depends(auth.get_current_user_uid)):
    memory = retrieve_in_progress_conversation(uid)
    if not memory:
        raise HTTPException(status_code=404, detail="Memory in progress not found")
    redis_db.remove_in_progress_conversation_id(uid)

    memory = Conversation(**memory)
    conversations_db.update_conversation_status(uid, memory.id, ConversationStatus.processing)
    memory = process_conversation(uid, memory.language, memory, force_process=True)
    messages = trigger_external_integrations(uid, memory)
    return CreateMemoryResponse(memory=memory, messages=messages)


# class TranscriptRequest(BaseModel):
#     transcript: str

# @router.post('/v2/test-memory', response_model= [], tags=['memories'])
# def process_test_memory(
#         request: TranscriptRequest, uid: str = Depends(auth.get_current_user_uid)
# ):
#   st =  get_transcript_structure(request.transcript, datetime.now(),'en','Asia/Kolkata')
#   return [st.json()]

@router.post('/v1/memories/{memory_id}/reprocess', response_model=Conversation, tags=['memories'])
def reprocess_memory(
        memory_id: str, language_code: Optional[str] = None, uid: str = Depends(auth.get_current_user_uid)
):
    """
    Whenever a user wants to reprocess a memory, or wants to force process a discarded one
    :return: The updated memory after reprocessing.
    """

    memory = conversations_db.get_conversation(uid, memory_id)
    if memory is None:
        raise HTTPException(status_code=404, detail="Memory not found")
    memory = Conversation(**memory)
    if not language_code:
        language_code = memory.language or 'en'

    return process_conversation(uid, language_code, memory, force_process=True, is_reprocess=True)


@router.get('/v1/memories', response_model=List[Conversation], tags=['memories'])
def get_memories(limit: int = 100, offset: int = 0, statuses: str = "", include_discarded: bool = True,
                 uid: str = Depends(auth.get_current_user_uid)):
    print('get_memories', uid, limit, offset, statuses)
    return conversations_db.get_conversations(uid, limit, offset, include_discarded=include_discarded,
                                              statuses=statuses.split(",") if len(statuses) > 0 else [])


@router.get("/v1/memories/{memory_id}", response_model=Conversation, tags=['memories'])
def get_memory_by_id(memory_id: str, uid: str = Depends(auth.get_current_user_uid)):
    return _get_memory_by_id(uid, memory_id)


@router.patch("/v1/memories/{memory_id}/title", tags=['memories'])
def patch_memory_title(memory_id: str, title: str, uid: str = Depends(auth.get_current_user_uid)):
    _get_memory_by_id(uid, memory_id)
    conversations_db.update_conversation_title(uid, memory_id, title)
    return {'status': 'Ok'}


@router.get("/v1/memories/{memory_id}/photos", response_model=List[ConversationPhoto], tags=['memories'])
def get_memory_photos(memory_id: str, uid: str = Depends(auth.get_current_user_uid)):
    _get_memory_by_id(uid, memory_id)
    return conversations_db.get_conversation_photos(uid, memory_id)


@router.get(
    "/v1/memories/{memory_id}/transcripts", response_model=Dict[str, List[TranscriptSegment]], tags=['memories']
)
def get_memory_transcripts_by_models(memory_id: str, uid: str = Depends(auth.get_current_user_uid)):
    _get_memory_by_id(uid, memory_id)
    return conversations_db.get_conversation_transcripts_by_model(uid, memory_id)


@router.delete("/v1/memories/{memory_id}", status_code=204, tags=['memories'])
def delete_memory(memory_id: str, uid: str = Depends(auth.get_current_user_uid)):
    print('delete_memory', memory_id, uid)
    conversations_db.delete_conversation(uid, memory_id)
    memories_db.delete_memories_for_conversation(uid, memory_id)
    delete_vector(memory_id)
    return {"status": "Ok"}


@router.get("/v1/memories/{memory_id}/recording", response_model=dict, tags=['memories'])
def memory_has_audio_recording(memory_id: str, uid: str = Depends(auth.get_current_user_uid)):
    _get_memory_by_id(uid, memory_id)
    return {'has_recording': get_conversation_recording_if_exists(uid, memory_id) is not None}


@router.patch("/v1/memories/{memory_id}/events", response_model=dict, tags=['memories'])
def set_memory_events_state(
        memory_id: str, data: SetConversationEventsStateRequest, uid: str = Depends(auth.get_current_user_uid)
):
    memory = _get_memory_by_id(uid, memory_id)
    memory = Conversation(**memory)
    events = memory.structured.events
    for i, event_idx in enumerate(data.events_idx):
        if event_idx >= len(events):
            continue
        events[event_idx].created = data.values[i]

    conversations_db.update_conversation_events(uid, memory_id, [event.dict() for event in events])
    return {"status": "Ok"}


@router.patch("/v1/memories/{memory_id}/action-items", response_model=dict, tags=['memories'])
def set_action_item_status(data: SetConversationActionItemsStateRequest, memory_id: str,
                           uid=Depends(auth.get_current_user_uid)):
    memory = _get_memory_by_id(uid, memory_id)
    memory = Conversation(**memory)
    action_items = memory.structured.action_items
    for i, action_item_idx in enumerate(data.items_idx):
        if action_item_idx >= len(action_items):
            continue
        action_items[action_item_idx].completed = data.values[i]

    conversations_db.update_conversation_action_items(uid, memory_id,
                                                      [action_item.dict() for action_item in action_items])
    return {"status": "Ok"}


@router.delete("/v1/memories/{memory_id}/action-items", response_model=dict, tags=['memories'])
def delete_action_item(data: DeleteActionItemRequest, memory_id: str, uid=Depends(auth.get_current_user_uid)):
    print('here inside of delete action item')
    memory = _get_memory_by_id(uid, memory_id)
    memory = Conversation(**memory)
    action_items = memory.structured.action_items
    for i, action_item in enumerate(action_items):
        if action_item.description == data.description:
            action_item.deleted = True
    conversations_db.update_conversation_action_items(uid, memory_id,
                                                      [action_item.dict() for action_item in action_items])
    return {"status": "Ok"}


@router.patch('/v1/memories/{memory_id}/segments/{segment_idx}/assign', response_model=Conversation, tags=['memories'])
def set_assignee_memory_segment(
        memory_id: str, segment_idx: int, assign_type: str, value: Optional[str] = None,
        use_for_speech_training: bool = True, uid: str = Depends(auth.get_current_user_uid)
):
    """
    Another complex endpoint.

    Modify the assignee of a segment in the transcript of a memory.
    But,
    if `use_for_speech_training` is True, the corresponding audio segment will be used for speech training.

    Speech training of whom?

    If `assign_type` is 'is_user', the segment will be used for the user speech training.
    If `assign_type` is 'person_id', the segment will be used for the person with the given id speech training.

    What is required for a segment to be used for speech training?
    1. The segment must have more than 5 words.
    2. The memory audio file shuold be already stored in the user's bucket.

    :return: The updated memory.
    """
    print('set_assignee_memory_segment', memory_id, segment_idx, assign_type, value, use_for_speech_training, uid)
    memory = _get_memory_by_id(uid, memory_id)
    memory = Conversation(**memory)

    if value == 'null':
        value = None

    is_unassigning = value is None or value is False

    if assign_type == 'is_user':
        memory.transcript_segments[segment_idx].is_user = bool(value) if value is not None else False
        memory.transcript_segments[segment_idx].person_id = None
    elif assign_type == 'person_id':
        memory.transcript_segments[segment_idx].is_user = False
        memory.transcript_segments[segment_idx].person_id = value
    else:
        print(assign_type)
        raise HTTPException(status_code=400, detail="Invalid assign type")

    conversations_db.update_conversation_segments(uid, memory_id,
                                                  [segment.dict() for segment in memory.transcript_segments])
    # thinh's note: disabled for now
    # segment_words = len(memory.transcript_segments[segment_idx].text.split(' '))
    # # TODO: can do this async
    # if use_for_speech_training and not is_unassigning and segment_words > 5:  # some decent sample at least
    #     person_id = value if assign_type == 'person_id' else None
    #     expand_speech_profile(memory_id, uid, segment_idx, assign_type, person_id)
    # else:
    #     path = f'{memory_id}_segment_{segment_idx}.wav'
    #     delete_additional_profile_audio(uid, path)
    #     delete_speech_sample_for_people(uid, path)

    return memory


@router.patch('/v1/memories/{memory_id}/assign-speaker/{speaker_id}', response_model=Conversation, tags=['memories'])
def set_assignee_memory_segment(
        memory_id: str, speaker_id: int, assign_type: str, value: Optional[str] = None,
        use_for_speech_training: bool = True, uid: str = Depends(auth.get_current_user_uid)
):
    """
    Another complex endpoint.

    Modify the assignee of all segments in the transcript of a memory with the given speaker_id.
    But,
    if `use_for_speech_training` is True, the corresponding audio segment will be used for speech training.

    Speech training of whom?

    If `assign_type` is 'is_user', the segment will be used for the user speech training.
    If `assign_type` is 'person_id', the segment will be used for the person with the given id speech training.

    What is required for a segment to be used for speech training?
    1. The segment must have more than 5 words.
    2. The memory audio file should be already stored in the user's bucket.

    :return: The updated memory.
    """
    print('set_assignee_memory_segment', memory_id, speaker_id, assign_type, value, use_for_speech_training, uid)
    memory = _get_memory_by_id(uid, memory_id)
    memory = Conversation(**memory)

    if value == 'null':
        value = None

    is_unassigning = value is None or value is False

    if assign_type == 'is_user':
        for segment in memory.transcript_segments:
            if segment.speaker_id == speaker_id:
                segment.is_user = bool(value) if value is not None else False
                segment.person_id = None
    elif assign_type == 'person_id':
        for segment in memory.transcript_segments:
            if segment.speaker_id == speaker_id:
                print(segment.speaker_id, speaker_id, value)
                segment.is_user = False
                segment.person_id = value
    else:
        print(assign_type)
        raise HTTPException(status_code=400, detail="Invalid assign type")

    conversations_db.update_conversation_segments(uid, memory_id,
                                                  [segment.dict() for segment in memory.transcript_segments])
    # This will be used when we setup recording for conversations, not used for now
    # get the segment with the most words with the speaker_id
    # segment_idx = 0
    # segment_words = 0
    # for segment in memory.transcript_segments:
    #     if segment.speaker == speaker_id:
    #         if len(segment.text.split(' ')) > segment_words:
    #             segment_words = len(segment.text.split(' '))
    #             if segment_words > 5:
    #                 segment_idx = segment.idx
    #
    # if use_for_speech_training and not is_unassigning and segment_words > 5:  # some decent sample at least
    #     person_id = value if assign_type == 'person_id' else None
    #     expand_speech_profile(memory_id, uid, segment_idx, assign_type, person_id)
    # else:
    #     path = f'{memory_id}_segment_{segment_idx}.wav'
    #     delete_additional_profile_audio(uid, path)
    #     delete_speech_sample_for_people(uid, path)

    return memory


# *********************************************
# ************* SHARING MEMORIES **************
# *********************************************

@router.patch('/v1/memories/{memory_id}/visibility', tags=['memories'])
def set_memory_visibility(
        memory_id: str, value: ConversationVisibility, uid: str = Depends(auth.get_current_user_uid)
):
    print('update_memory_visibility', memory_id, value, uid)
    _get_memory_by_id(uid, memory_id)
    conversations_db.set_conversation_visibility(uid, memory_id, value)
    if value == ConversationVisibility.private:
        redis_db.remove_conversation_to_uid(memory_id)
        redis_db.remove_public_conversation(memory_id)
    else:
        redis_db.store_conversation_to_uid(memory_id, uid)
        redis_db.add_public_conversation(memory_id)

    return {"status": "Ok"}


@router.get("/v1/memories/{memory_id}/shared", response_model=Conversation, tags=['memories'])
def get_shared_memory_by_id(memory_id: str):
    uid = redis_db.get_conversation_uid(memory_id)
    if not uid:
        raise HTTPException(status_code=404, detail="Memory is private")

    # TODO: include speakers and people matched?
    # TODO: other fields that  shouldn't be included?
    memory = _get_memory_by_id(uid, memory_id)
    visibility = memory.get('visibility', ConversationVisibility.private)
    if not visibility or visibility == ConversationVisibility.private:
        raise HTTPException(status_code=404, detail="Memory is private")
    memory = Conversation(**memory)
    memory.geolocation = None
    return memory


@router.get("/v1/public-memories", response_model=List[Conversation], tags=['memories'])
def get_public_memories(offset: int = 0, limit: int = 1000):
    memories = redis_db.get_public_conversations()
    data = []

    memory_uids = redis_db.get_conversation_uids(memories)

    data = [[uid, memory_id] for memory_id, uid in memory_uids.items() if uid]
    # TODO: sort in some way to have proper pagination

    memories = conversations_db.run_get_public_conversations(data[offset:offset + limit])
    for memory in memories:
        memory['geolocation'] = None
    return memories


@router.post("/v1/memories/search", response_model=dict, tags=['memories'])
def search_memories_endpoint(search_request: SearchRequest, uid: str = Depends(auth.get_current_user_uid)):
    return search_conversations(query=search_request.query, page=search_request.page,
                                per_page=search_request.per_page, uid=uid,
                                include_discarded=search_request.include_discarded)

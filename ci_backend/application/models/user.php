<?php 

class User extends CI_Model {

    private $table_name = 'dbo.users';

    function __construct()
    {
        parent::__construct();
    }
    
    function get($id)
    {
        $this->db->where('id', $id);
        $query = $this->db->get($this->table_name);
        return $query->result();
    }

    // function insert_entry()
    // {
    //     $this->title   = $_POST['title']; // please read the below note
    //     $this->content = $_POST['content'];
    //     $this->date    = time();

    //     $this->db->insert('entries', $this);
    // }

    // function update_entry()
    // {
    //     $this->title   = $_POST['title'];
    //     $this->content = $_POST['content'];
    //     $this->date    = time();

    //     $this->db->update('entries', $this, array('id' => $_POST['id']));
    // }

}